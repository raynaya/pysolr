"""
custom_requests
~~~~~~~~~~~~~~~~

Wrapper over requests library to provide utility stuff.
"""

from requests import Session
from requests import adapters
from requests_futures.sessions import FuturesSession


CONNECT_TIMEOUT = 5.0
READ_TIMEOUT = 15.0

NUM_POOLS = 100
POOL_MAXSIZE = 1000


class CRequests:

    def __init__(self, CONNECT_TIMEOUT=CONNECT_TIMEOUT, READ_TIMEOUT=READ_TIMEOUT, stream=False):
        self.requests = FuturesSession()
        self.requests.stream = stream
        self.requests.trust_env = False
        self.requests.mount('http://', adapters.HTTPAdapter(pool_connections=NUM_POOLS,
                                                            pool_maxsize=POOL_MAXSIZE,
                                                            pool_block=False))
        self.requests.mount('https://', adapters.HTTPAdapter(pool_connections=NUM_POOLS,
                                                             pool_block=False,
                                                             pool_maxsize=POOL_MAXSIZE))

        self.tuple = (CONNECT_TIMEOUT, READ_TIMEOUT)

    def request(self, method, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future = self.requests.request(method, url, **kwargs)
        return future.result(timeout=READ_TIMEOUT)

    def get(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future=self.requests.get(url, **kwargs)
        return future.result(timeout=READ_TIMEOUT)

    def options(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future= self.requests.options(url, **kwargs)
        return future.result(timeout=READ_TIMEOUT)

    def head(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future= self.requests.head(url, **kwargs)
        return future.result(timeout=READ_TIMEOUT)

    def post(self, url, data=None, json=None, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future= self.requests.post(url, data=data, json=json, **kwargs)
        return future.result(timeout=READ_TIMEOUT)

    def put(self, url, data=None, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future= self.requests.put(url, data=data, **kwargs)
        return future.result(timeout=READ_TIMEOUT)

    def patch(self, url, data=None, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future= self.requests.patch(url, data=data, **kwargs)
        return future.result(timeout=READ_TIMEOUT)

    def delete(self, url, **kwargs):
        kwargs.setdefault('timeout', self.tuple)
        future= self.requests.delete(url, **kwargs)
        return future.result(timeout=READ_TIMEOUT)


    def close(self):
        self.requests.close()
