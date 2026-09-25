"""Exercise permissions and synchronized room lifecycles through real ASGI sockets."""

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from server.main import app, rooms


@pytest.fixture
def client():
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
