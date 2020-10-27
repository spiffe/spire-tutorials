package envoy.authz

import input.attributes.request.http as http_request

default allow = false

# allow Frontend service to access Backend service
allow {
    valid_path
    http_request.method == "GET"
    svc_spiffe_id == "spiffe://example.org/ns/default/sa/default/frontend"
}

svc_spiffe_id = spiffe_id {
    [_, _, uri_type_san] := split(http_request.headers["x-forwarded-client-cert"], ";")
    [_, spiffe_id] := split(uri_type_san, "=")
}

valid_path {
    glob.match("/balances/*", [], http_request.path)
}

valid_path {
    glob.match("/profiles/*", [], http_request.path)
}

valid_path {
    glob.match("/transactions/*", [], http_request.path)
}
