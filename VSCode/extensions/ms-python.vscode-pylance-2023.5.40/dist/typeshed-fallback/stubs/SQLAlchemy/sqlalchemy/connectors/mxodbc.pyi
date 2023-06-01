from _typeshed import Incomplete

from . import Connector

class MxODBCConnector(Connector):
    driver: str
    supports_sane_multi_rowcount: bool
    supports_unicode_statements: bool
    supports_unicode_binds: bool
    supports_native_decimal: bool
    @classmethod
    def dbapi(cls): ...
    def on_connect(self): ...
    def create_connect_args(self, url): ...
    def is_disconnect(self, e, connection, cursor): ...
    def do_executemany(self, cursor, statement, parameters, context: Incomplete | None = None) -> None: ...
    def do_execute(self, cursor, statement, parameters, context: Incomplete | None = None) -> None: ...
