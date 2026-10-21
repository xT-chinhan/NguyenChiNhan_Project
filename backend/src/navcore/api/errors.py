import logging
import uuid

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException


class ApiError(Exception):
    def __init__(self, code: str, status: int, message: str, details: list | None = None):
        super().__init__(code)
        self.code, self.status, self.message, self.details = code, status, message, details or []


def error_response(request, code, status, message, details=None):
    request_id = getattr(request.state, "request_id", str(uuid.uuid4()))
    return JSONResponse(
        {
            "error": {
                "code": code,
                "message": message,
                "request_id": request_id,
                "details": details or [],
            }
        },
        status_code=status,
        headers={"X-Request-ID": request_id},
    )


def install_handlers(app):
    @app.exception_handler(ApiError)
    async def known(request: Request, error: ApiError):
        response = error_response(request, error.code, error.status, error.message, error.details)
        if error.code == "SESSION_CAPACITY":
            response.headers["Retry-After"] = "1"
        return response

    @app.exception_handler(RequestValidationError)
    async def validation(request: Request, error: RequestValidationError):
        details = [{"location": list(item["loc"]), "type": item["type"]} for item in error.errors()]
        return error_response(request, "VALIDATION_ERROR", 422, "Invalid request", details)

    @app.exception_handler(HTTPException)
    async def http(request: Request, error: HTTPException):
        codes = {
            401: "AUTH_REQUIRED",
            403: "ROLE_FORBIDDEN",
            404: "RESOURCE_NOT_FOUND",
            413: "PAYLOAD_TOO_LARGE",
            422: "VALIDATION_ERROR",
        }
        return error_response(
            request,
            codes.get(error.status_code, "HTTP_ERROR"),
            error.status_code,
            "Request could not be completed",
        )

    @app.exception_handler(Exception)
    async def unexpected(request: Request, error: Exception):
        logging.getLogger("navcore").exception(
            "request_failed", extra={"fields": {"request_id": request.state.request_id}}
        )
        return error_response(request, "INTERNAL_ERROR", 500, "Internal server error")


class RequestLimits:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        request_id = str(uuid.uuid4())
        scope.setdefault("state", {})["request_id"] = request_id
        body = bytearray()
        while True:
            event = await receive()
            if event["type"] == "http.disconnect":
                return
            chunk = event.get("body", b"")
            if len(body) + len(chunk) > 4 * 1024 * 1024:
                request = Request(scope)
                response = error_response(request, "PAYLOAD_TOO_LARGE", 413, "Request is too large")
                return await response(scope, receive, send)
            body.extend(chunk)
            if not event.get("more_body", False):
                break
        delivered = False

        async def limited_receive():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        async def identified_send(event):
            if event["type"] == "http.response.start":
                event["headers"] = [
                    (k, v) for k, v in event.get("headers", []) if k.lower() != b"x-request-id"
                ]
                event["headers"].append((b"x-request-id", request_id.encode()))
            await send(event)

        await self.app(scope, limited_receive, identified_send)
