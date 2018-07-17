"""
custom_requests
~~~~~~~~~~~~~~~~

Wrapper over requests library to provide utility stuff.
"""

from requests import Session
from requests import adapters

CONNECT_TIMEOUT = 5.0
READ_TIMEOUT = 15.0

NUM_POOLS = 100
POOL_MAXSIZE = 400


class CRequests:

    def __init__(self, CONNECT_TIMEOUT=CONNECT_TIMEOUT, READ_TIMEOUT=READ_TIMEOUT, stream=False):
        self.requests = Session()
        self.requests.stream = stream
        self.requests.trust_env = False
        self.requests.mount('http://', adapters.HTTPAdapter(pool_connections=NUM_POOLS,
                                                            pool_maxsize=POOL_MAXSIZE,
                                                            pool_block=True))
        self.requests.mount('https://', adapters.HTTPAdapter(pool_connections=NUM_POOLS,
                                                             pool_block=True,
                                                             pool_maxsize=POOL_MAXSIZE))

        self.tuple = (CONNECT_TIMEOUT, READ_TIMEOUT)

    def request(self, method, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.request(method, url, **kwargs)

    def get(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.get(url, **kwargs)

    def options(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.options(url, **kwargs)

    def head(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.head(url, **kwargs)

    def post(self, url, data=None, json=None, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.post(url, data=data, json=json, **kwargs)

    def put(self, url, data=None, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.put(url, data=data, **kwargs)

    def patch(self, url, data=None, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.patch(url, data=data, **kwargs)

    def delete(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        return self.requests.delete(url, **kwargs)

    def close(self):
        self.requests.close()
