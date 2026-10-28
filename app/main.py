import os

from flask import Flask, jsonify, request

app = Flask(__name__)

# Lab dataset: in a real system this would be backed by a database.
# One single source of truth used by every endpoint.
ITEMS = {
    1: {'id': 1, 'name': 'router', 'stock': 8},
    2: {'id': 2, 'name': 'switch', 'stock': 3},
}

THRESHOLD_MIN = 0
THRESHOLD_MAX = 100


@app.get('/')
def index():
    return jsonify(service='inventory-api', version=os.getenv('APP_VERSION', 'dev'), status='running')


@app.get('/health')
def health():
    return jsonify(status='ok'), 200


@app.get('/api/items')
def items():
    return jsonify(items=list(ITEMS.values()))


@app.get('/api/items/low-stock')
def low_stock():
    """Return items whose stock is strictly below ?threshold=N (0 <= N <= 100)."""
    raw = request.args.get('threshold')
    if raw is None or raw.strip() == '':
        return jsonify(error='threshold query parameter is required'), 400
    try:
        threshold = int(raw.strip())
    except ValueError:
        return jsonify(error='threshold must be an integer'), 400
    if not THRESHOLD_MIN <= threshold <= THRESHOLD_MAX:
        return jsonify(error=f'threshold must be between {THRESHOLD_MIN} and {THRESHOLD_MAX}'), 400
    result = [item for item in ITEMS.values() if item['stock'] < threshold]
    return jsonify(threshold=threshold, items=result), 200


@app.get('/api/items/<int:item_id>')
def item_detail(item_id):
    if item_id not in ITEMS:
        return jsonify(error='item not found'), 404
    return jsonify(ITEMS[item_id]), 200


@app.errorhandler(404)
def not_found(_error):
    return jsonify(error='not found'), 404


@app.errorhandler(405)
def method_not_allowed(_error):
    return jsonify(error='method not allowed'), 405


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
