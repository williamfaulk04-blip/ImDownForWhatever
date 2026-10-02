"""Exercise permissions and synchronized room lifecycles through real ASGI sockets."""

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from server.main import app, rooms
import server.main as main


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv('FASTPOLL_DB_PATH', str(tmp_path / 'rooms.sqlite3'))
    rooms.clear()
    with TestClient(app) as client:
        yield client
    rooms.clear()


def make_room(client):
    response = client.post('/api/rooms', json={'name': 'Host'})
    assert response.status_code == 201
    return response.json()


def headers(session):
    return {'Authorization': f'Bearer {session["session_token"]}'}


def join(client, host):
    response = client.post(f'/api/rooms/{host["room_code"]}/join', json={'name': 'Friend'})
    assert response.status_code == 200
    return response.json()


def start(client, host, duration=60):
    response = client.post(f'/api/rooms/{host["room_code"]}/polls', headers=headers(host),
                           json={'topic': 'Dinner?', 'options': ['Tacos', 'Pizza'], 'duration': duration})
    assert response.status_code == 201
    return response.json()['poll']


def authenticate(socket, session):
    socket.send_json({'session_token': session['session_token']})
    return until(socket, lambda event: event['event'] == 'STATE_UPDATE')


def until(socket, predicate):
    # Server emits a heartbeat snapshot every second; cap reads to avoid hangs.
    for _ in range(10):
        event = socket.receive_json()
        if predicate(event):
            return event
    pytest.fail('Expected state did not arrive within ten updates')


def vote(socket, poll, option):
    socket.send_json({'action': 'CAST_VOTE', 'poll_id': poll['id'], 'option_id': option})


def test_health_and_empty_lobby(client):
    assert client.get('/health').json() == {'status': 'healthy'}
    host = make_room(client)
    code = host['room_code']
    assert len(code) == 4 and code.isalnum() and code == code.upper()
    with client.websocket_connect(f'/ws/{code}') as socket:
        state = authenticate(socket, host)
        assert state['is_host'] and state['poll'] is None
        assert state['participants'][0]['online']
        assert host['session_token'] not in str(state)


def test_health_reports_storage_failure(client, monkeypatch):
    import sqlite3

    def fail():
        raise sqlite3.OperationalError('disk unavailable')

    monkeypatch.setattr(main.store, 'check', fail)
    response = client.get('/health')
    assert response.status_code == 503
    assert response.json() == {'detail': 'Room storage is not ready.'}


def test_host_permissions_lock_and_resume(client):
    host = make_room(client)
    friend = join(client, host)
    path = f'/api/rooms/{host["room_code"]}'
    assert client.patch(path, json={'is_open': False}).status_code == 401
    assert client.patch(path, headers=headers(friend), json={'is_open': False}).status_code == 403
    assert client.post(path + '/polls', headers=headers(friend), json={
        'topic': 'No', 'options': ['A', 'B'], 'duration': 30}).status_code == 403
    assert client.patch(path, headers=headers(host), json={'is_open': False}).status_code == 200
    assert client.post(path + '/join', json={'name': 'New friend'}).status_code == 403
    resumed = client.post(path + '/join', json={'name': 'Friend', 'session_token': friend['session_token']})
    assert resumed.json() == friend
    assert client.post(path + '/join', json={'name': 'Imposter', 'session_token': 'fake'}).status_code == 401
    assert client.patch(path, headers=headers(host), json={'is_open': True}).status_code == 200
    assert client.post(path + '/join', json={'name': 'New friend'}).status_code == 200


def test_two_clients_vote_close_and_second_poll(client):
    host = make_room(client)
    friend = join(client, host)
    path = f'/api/rooms/{host["room_code"]}'
    with client.websocket_connect(f'/ws/{host["room_code"]}') as a, client.websocket_connect(f'/ws/{host["room_code"]}') as b:
        authenticate(a, host)
        assert not authenticate(b, friend)['is_host']
        first = start(client, host)
        until(a, lambda e: e.get('poll') is not None)
        until(b, lambda e: e.get('poll') is not None)
        vote(b, first, 1)
        own = until(b, lambda e: e.get('poll', {}).get('selected_option') == 1)
        shared = until(a, lambda e: e.get('poll', {}).get('options', [{}, {}])[1].get('votes') == 1)
        assert own['poll']['options'][1]['votes'] == 1
        assert shared['poll']['selected_option'] is None
        vote(b, first, 0)  # first vote wins
        state = until(b, lambda e: e.get('poll', {}).get('selected_option') is not None)
        assert state['poll']['selected_option'] == 1
        assert client.post(path + f'/polls/{first["id"]}/close', headers=headers(friend)).status_code == 403
        assert client.post(path + '/polls', headers=headers(host), json={
            'topic': 'Another', 'options': ['A', 'B'], 'duration': 30}).status_code == 409
        assert client.post(path + f'/polls/{first["id"]}/close', headers=headers(host)).status_code == 200
        closed = until(b, lambda e: e.get('poll', {}).get('status') == 'closed')
        assert closed['poll']['winner_ids'] == [1]
        second = start(client, host)
        fresh = until(b, lambda e: e.get('poll', {}).get('id') == second['id'])
        assert fresh['poll']['selected_option'] is None
        assert sum(o['votes'] for o in fresh['poll']['options']) == 0
        vote(b, first, 0)  # delayed vote must not count in the next round
        assert until(b, lambda e: e['event'] == 'ERROR')['message'] == 'This poll is no longer current.'
        assert client.post(path + f'/polls/{first["id"]}/close', headers=headers(host)).status_code == 409
        vote(b, second, 0)
        until(b, lambda e: e.get('poll', {}).get('selected_option') == 0)


def test_reconnect_restores_vote_and_host_role(client):
    host = make_room(client)
    poll = start(client, host)
    url = f'/ws/{host["room_code"]}'
    with client.websocket_connect(url) as socket:
        authenticate(socket, host)
        vote(socket, poll, 0)
        until(socket, lambda e: e['poll']['selected_option'] == 0)
    with client.websocket_connect(url) as socket:
        state = authenticate(socket, host)
        assert state['is_host'] and state['poll']['selected_option'] == 0
        vote(socket, poll, 1)
        assert until(socket, lambda e: e['poll']['selected_option'] is not None)['poll']['options'][0]['votes'] == 1


def test_automatic_expiration_and_late_vote(client):
    host = make_room(client)
    with client.websocket_connect(f'/ws/{host["room_code"]}') as socket:
        authenticate(socket, host)
        poll = start(client, host, duration=1)
        state = until(socket, lambda e: e.get('poll') and e['poll']['status'] == 'closed')
        assert state['poll']['time_left'] == 0 and state['poll']['winner_ids'] == []
        vote(socket, poll, 0)
        assert until(socket, lambda e: e['event'] == 'ERROR')['message'] == 'Poll is closed.'


@pytest.mark.parametrize('option', [-1, 2, True, '0', None])
def test_invalid_votes(client, option):
    host = make_room(client)
    poll = start(client, host)
    with client.websocket_connect(f'/ws/{host["room_code"]}') as socket:
        authenticate(socket, host)
        vote(socket, poll, option)
        assert until(socket, lambda e: e['event'] == 'ERROR')['message'] == 'Invalid option.'
        assert not rooms[host['room_code']].poll.votes


def test_malformed_message_does_not_disconnect(client):
    host = make_room(client)
    with client.websocket_connect(f'/ws/{host["room_code"]}') as socket:
        authenticate(socket, host)
        socket.send_text('not json')
        assert until(socket, lambda e: e['event'] == 'ERROR')
        socket.send_json([])
        assert until(socket, lambda e: e['event'] == 'ERROR')
        poll = start(client, host)
        vote(socket, poll, 0)
        until(socket, lambda e: e.get('poll') and e['poll']['selected_option'] == 0)


def test_unknown_room_and_invalid_socket_credentials(client):
    assert client.post('/api/rooms/XXXX/join', json={'name': 'Friend'}).status_code == 404
    with client.websocket_connect('/ws/XXXX') as socket:
        with pytest.raises(WebSocketDisconnect) as closed:
            socket.receive_json()
        assert closed.value.code == 4404
    host = make_room(client)
    with client.websocket_connect(f'/ws/{host["room_code"]}') as socket:
        socket.send_json({'session_token': 'fake'})
        with pytest.raises(WebSocketDisconnect) as closed:
            socket.receive_json()
        assert closed.value.code == 4401


def test_validation_and_tie(client):
    assert client.post('/api/rooms', json={'name': '  '}).status_code == 422
    host = make_room(client)
    path = f'/api/rooms/{host["room_code"]}'
    for options in [['A', 'a'], [' ', 'B'], ['A']]:
        assert client.post(path + '/polls', headers=headers(host), json={
            'topic': 'Pick', 'options': options, 'duration': 30}).status_code == 422
    friend = join(client, host)
    poll = start(client, host)
    with client.websocket_connect(f'/ws/{host["room_code"]}') as a, client.websocket_connect(f'/ws/{host["room_code"]}') as b:
        authenticate(a, host)
        authenticate(b, friend)
        vote(a, poll, 0)
        until(a, lambda e: e['poll']['selected_option'] == 0)
        vote(b, poll, 1)
        until(b, lambda e: e['poll']['selected_option'] == 1)
        response = client.post(path + f'/polls/{poll["id"]}/close', headers=headers(host))
        assert response.json()['poll']['winner_ids'] == [0, 1]


def test_malformed_authentication_closes_socket(client):
    host = make_room(client)
    with client.websocket_connect(f'/ws/{host["room_code"]}') as socket:
        socket.send_text('not json')
        with pytest.raises(WebSocketDisconnect) as closed:
            socket.receive_json()
        assert closed.value.code == 4401


def add_category(client, host, name):
    return client.post(
        f'/api/rooms/{host["room_code"]}/categories',
        headers=headers(host),
        json={'name': name},
    )


def add_activity(client, host, category_id, name):
    return client.post(
        f'/api/rooms/{host["room_code"]}/categories/{category_id}/activities',
        headers=headers(host),
        json={'name': name},
    )


def test_wheel_empty_and_invalid_selection_errors(client):
    host = make_room(client)
    path = f'/api/rooms/{host["room_code"]}/wheel'
    assert client.post(path + '/category-spin', headers=headers(host)).status_code == 409
    assert client.post(path + '/activity-spin', headers=headers(host)).status_code == 409
    assert add_category(client, host, 'Games').status_code == 201
    category = rooms[host['room_code']].categories[0]
    assert client.post(path + '/activity-spin', headers=headers(host)).status_code == 409
    assert client.patch(
        f'/api/rooms/{host["room_code"]}/categories/missing',
        headers=headers(host), json={'name': 'Renamed'},
    ).status_code == 404
    assert client.post(
        f'/api/rooms/{host["room_code"]}/categories/missing/activities',
        headers=headers(host), json={'name': 'Tennis'},
    ).status_code == 404
    assert client.patch(
        f'/api/rooms/{host["room_code"]}/categories/{category.id}/activities/missing',
        headers=headers(host), json={'name': 'Tennis'},
    ).status_code == 404
    assert client.delete(
        f'/api/rooms/{host["room_code"]}/categories/{category.id}/activities/missing',
        headers=headers(host),
    ).status_code == 404
    assert category.activities == []


def test_wheel_edits_are_host_only_and_support_category_activity_crud(client):
    host = make_room(client)
    friend = join(client, host)
    path = f'/api/rooms/{host["room_code"]}'
    assert client.post(path + '/categories', headers=headers(friend), json={'name': 'Games'}).status_code == 403
    category_state = add_category(client, host, 'Games')
    assert category_state.status_code == 201
    category = category_state.json()['categories'][0]
    assert category['name'] == 'Games' and category['activities'] == []
    assert add_category(client, host, 'games').status_code == 422
    assert client.patch(
        path + f'/categories/{category["id"]}', headers=headers(friend), json={'name': 'Play'}
    ).status_code == 403
    state = client.patch(
        path + f'/categories/{category["id"]}', headers=headers(host), json={'name': 'Play'}
    ).json()
    assert state['categories'][0]['name'] == 'Play'
    activity_state = add_activity(client, host, category['id'], 'Mario Kart')
    activity = activity_state.json()['categories'][0]['activities'][0]
    assert activity['name'] == 'Mario Kart'
    activity_path = path + f'/categories/{category["id"]}/activities/{activity["id"]}'
    assert client.patch(activity_path, headers=headers(friend), json={'name': 'Kart'}).status_code == 403
    assert client.delete(activity_path, headers=headers(friend)).status_code == 403
    renamed = client.patch(activity_path, headers=headers(host), json={'name': 'Kart'}).json()
    assert renamed['categories'][0]['activities'][0]['name'] == 'Kart'
    removed = client.delete(activity_path, headers=headers(host)).json()
    assert removed['categories'][0]['activities'] == []
    assert client.delete(path + f'/categories/{category["id"]}', headers=headers(friend)).status_code == 403
    assert client.delete(path + f'/categories/{category["id"]}', headers=headers(host)).json()['categories'] == []


def test_server_authoritative_spins_broadcast_and_restore_current_wheel(client, monkeypatch):
    host = make_room(client)
    friend = join(client, host)
    add_category(client, host, 'Games')
    add_category(client, host, 'Food')
    categories = rooms[host['room_code']].categories
    add_activity(client, host, categories[1].id, 'Tacos')
    add_activity(client, host, categories[1].id, 'Pizza')
    # Selection is made by the server's chooser; the request contains no result.
    monkeypatch.setattr(main.secrets, 'choice', lambda choices: choices[-1])
    url = f'/ws/{host["room_code"]}'
    with client.websocket_connect(url) as a, client.websocket_connect(url) as b:
        authenticate(a, host)
        authenticate(b, friend)
        path = f'/api/rooms/{host["room_code"]}/wheel'
        category_response = client.post(path + '/category-spin', headers=headers(host))
        assert category_response.status_code == 200
        category_wheel = category_response.json()['wheel']
        assert category_wheel['phase'] == 'category'
        assert category_wheel['status'] == 'finished'
        assert category_wheel['selected_category_id'] == categories[1].id
        assert category_wheel['result'] == 'Food'
        assert category_wheel['spin_id']
        for socket in (a, b):
            update = until(socket, lambda event: event.get('wheel', {}).get('spin_id') == category_wheel['spin_id'])
            assert update['wheel'] == category_wheel

        activity_response = client.post(path + '/activity-spin', headers=headers(host))
        activity_wheel = activity_response.json()['wheel']
        assert activity_wheel['phase'] == 'activity'
        assert activity_wheel['selected_category_id'] == categories[1].id
        assert activity_wheel['selected_activity_id'] == categories[1].activities[1].id
        assert activity_wheel['result'] == 'Pizza'
        assert activity_wheel['spin_id'] != category_wheel['spin_id']
        for socket in (a, b):
            update = until(socket, lambda event: event.get('wheel', {}).get('spin_id') == activity_wheel['spin_id'])
            assert update['wheel'] == activity_wheel

        # Re-spinning a category starts a fresh category phase and clears activity.
        respun = client.post(path + '/category-spin', headers=headers(host)).json()['wheel']
        assert respun['spin_id'] != activity_wheel['spin_id']
        assert respun['phase'] == 'category'
        assert respun['selected_activity_id'] is None

    # A new authenticated socket receives the current snapshot, not a replay dependency.
    with client.websocket_connect(url) as reconnected:
        snapshot = authenticate(reconnected, friend)
        assert snapshot['wheel'] == respun


def test_activity_spin_rejects_guest_and_empty_selected_category(client):
    host = make_room(client)
    friend = join(client, host)
    category = add_category(client, host, 'Games').json()['categories'][0]
    path = f'/api/rooms/{host["room_code"]}/wheel'
    assert client.post(path + '/category-spin', headers=headers(friend)).status_code == 403
    client.post(path + '/category-spin', headers=headers(host))
    assert client.post(path + '/activity-spin', headers=headers(friend)).status_code == 403
    assert client.post(path + '/activity-spin', headers=headers(host)).status_code == 409
    assert add_activity(client, host, category['id'], 'Minecraft').status_code == 201
    selected = client.post(path + '/activity-spin', headers=headers(host)).json()['wheel']
    assert selected['phase'] == 'activity'
    assert selected['selected_category_id'] == category['id']
    assert selected['result'] == 'Minecraft'
    cleared = client.delete(
        f'/api/rooms/{host["room_code"]}/categories/{category["id"]}/activities/{selected["selected_activity_id"]}',
        headers=headers(host),
    ).json()['wheel']
    assert cleared['spin_id'] is None
    assert cleared['phase'] is None
    assert cleared['selected_category_id'] is None
    assert cleared['selected_activity_id'] is None


def test_restart_restores_room_choices_votes_and_host(tmp_path, monkeypatch):
    database = tmp_path / 'rooms.sqlite3'
    monkeypatch.setenv('FASTPOLL_DB_PATH', str(database))
    with TestClient(app) as client:
        host = make_room(client)
        friend = join(client, host)
        path = f'/api/rooms/{host["room_code"]}'
        category = client.post(path + '/categories', headers=headers(host),
                               json={'name': 'Games'}).json()['categories'][0]
        assert client.post(path + f'/categories/{category["id"]}/activities',
                           headers=headers(host), json={'name': 'Mario Kart'}).status_code == 201
        client.post(path + '/wheel/category-spin', headers=headers(host))
        spin = client.post(path + '/wheel/activity-spin', headers=headers(host)).json()['wheel']
        poll = start(client, host, duration=3600)
        with client.websocket_connect(f'/ws/{host["room_code"]}') as socket:
            authenticate(socket, friend)
            vote(socket, poll, 1)
            until(socket, lambda event: event.get('poll', {}).get('selected_option') == 1)
        client.patch(path, headers=headers(host), json={'is_open': False})
        # Data is committed before shutdown; raw bearer credentials are never stored.
        import sqlite3
        with sqlite3.connect(database) as db:
            saved = db.execute('SELECT payload FROM rooms').fetchone()[0]
        assert 'Mario Kart' in saved
        assert host['session_token'] not in saved
        assert friend['session_token'] not in saved
    rooms.clear()
    with TestClient(app) as restarted:
        assert restarted.post(path + '/join', json={'name': 'New'}).status_code == 403
        for session in (host, friend):
            assert restarted.post(path + '/join', json={
                'name': session['name'], 'session_token': session['session_token'],
            }).json() == session
        with restarted.websocket_connect(f'/ws/{host["room_code"]}') as socket:
            restored = authenticate(socket, friend)
            assert restored['poll']['selected_option'] == 1
            assert restored['poll']['options'][1]['votes'] == 1
            assert restored['wheel'] == spin
            assert restored['categories'][0]['activities'][0]['name'] == 'Mario Kart'
            assert not restored['is_host']
            assert sum(person['online'] for person in restored['participants']) == 1
        assert restarted.post(path + f'/polls/{poll["id"]}/close', headers=headers(friend)).status_code == 403
        assert restarted.post(path + f'/polls/{poll["id"]}/close', headers=headers(host)).status_code == 200
    with TestClient(app) as restarted_again:
        with restarted_again.websocket_connect(f'/ws/{host["room_code"]}') as socket:
            restored = authenticate(socket, host)
            assert restored['is_host']
            assert restored['poll']['status'] == 'closed'
            assert restored['poll']['winner_ids'] == [1]


def test_poll_expires_during_server_downtime(tmp_path, monkeypatch):
    monkeypatch.setenv('FASTPOLL_DB_PATH', str(tmp_path / 'rooms.sqlite3'))
    with TestClient(app) as client:
        host = make_room(client)
        start(client, host, duration=30)
        deadline = rooms[host['room_code']].poll.ends_at
    monkeypatch.setattr(main.time, 'time', lambda: deadline + 10)
    with TestClient(app) as restarted:
        with restarted.websocket_connect(f'/ws/{host["room_code"]}') as socket:
            restored = authenticate(socket, host)
            assert restored['poll']['status'] == 'closed'
            assert restored['poll']['time_left'] == 0


def test_failed_save_does_not_acknowledge_or_keep_changes(client, monkeypatch):
    import sqlite3
    host = make_room(client)
    def fail(*args):
        raise sqlite3.OperationalError('disk full')
    monkeypatch.setattr(main.store, 'save', fail)
    response = client.post(f'/api/rooms/{host["room_code"]}/categories',
                           headers=headers(host), json={'name': 'Unsaved'})
    assert response.status_code == 503
    assert not rooms[host['room_code']].categories
    before = len(rooms)
    assert client.post('/api/rooms', json={'name': 'Unsaved host'}).status_code == 503
    assert len(rooms) == before
