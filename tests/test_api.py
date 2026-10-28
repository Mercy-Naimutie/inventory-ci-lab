import pytest

from app.main import ITEMS, app


@pytest.fixture
def client():
    app.config.update(TESTING=True)
    with app.test_client() as client:
        yield client


def expected_below(threshold):
    """Compute the expected result from the dataset instead of hardcoding it."""
    return sorted(item['id'] for item in ITEMS.values() if item['stock'] < threshold)


def ids(response):
    return sorted(item['id'] for item in response.get_json()['items'])


# ---------- starter tests ----------

def test_health(client):
    response = client.get('/health')
    assert response.status_code == 200
    assert response.get_json()['status'] == 'ok'


def test_items(client):
    response = client.get('/api/items')
    assert response.status_code == 200
    assert len(response.get_json()['items']) == len(ITEMS)


def test_item_not_found(client):
    response = client.get('/api/items/999')
    assert response.status_code == 404
    assert response.get_json()['error'] == 'item not found'


# ---------- Challenge 1: /api/items/low-stock ----------

def test_low_stock_filters_items_below_threshold(client):
    response = client.get('/api/items/low-stock?threshold=5')
    assert response.status_code == 200
    body = response.get_json()
    assert body['threshold'] == 5
    assert ids(response) == expected_below(5)
    assert all(item['stock'] < 5 for item in body['items'])


def test_low_stock_is_strictly_below_threshold(client):
    # An item whose stock equals the threshold must NOT be returned ...
    item = next(iter(ITEMS.values()))
    response = client.get(f"/api/items/low-stock?threshold={item['stock']}")
    assert response.status_code == 200
    assert item['id'] not in ids(response)
    # ... but one above its stock, it must be included.
    response = client.get(f"/api/items/low-stock?threshold={item['stock'] + 1}")
    assert item['id'] in ids(response)


@pytest.mark.parametrize('threshold', [0, 100])
def test_low_stock_accepts_range_boundaries(client, threshold):
    response = client.get(f'/api/items/low-stock?threshold={threshold}')
    assert response.status_code == 200
    assert ids(response) == expected_below(threshold)


def test_low_stock_zero_returns_empty_list(client):
    response = client.get('/api/items/low-stock?threshold=0')
    assert response.status_code == 200
    assert response.get_json()['items'] == []


@pytest.mark.parametrize('bad', ['-1', '101', 'abc', '5.5', '1e2', '', ' '])
def test_low_stock_rejects_invalid_threshold(client, bad):
    response = client.get('/api/items/low-stock', query_string={'threshold': bad})
    assert response.status_code == 400
    assert response.is_json
    assert 'error' in response.get_json()


def test_low_stock_requires_threshold(client):
    response = client.get('/api/items/low-stock')
    assert response.status_code == 400
    assert response.get_json()['error'] == 'threshold query parameter is required'


def test_low_stock_does_not_clash_with_item_detail(client):
    # /api/items/<int:id> must still work next to the static low-stock route.
    response = client.get('/api/items/1')
    assert response.status_code == 200
    assert response.get_json()['id'] == 1


def test_unknown_route_returns_json_404(client):
    response = client.get('/does-not-exist')
    assert response.status_code == 404
    assert response.is_json
