# nginx-proxy includes this file instead of vhost.d/default for MyETM, so keep the default too.
include /etc/nginx/vhost.d/default;

# MyETM's API gateway. Rails gives a verdict on each call under a Scenario that MyETM does not serve
# itself, and nginx passes the call through to the Scenario's engine, so no MyETM worker waits on the engine.
location ~ ^/api/v4/saved_scenarios/\d+/(?!(?:users|discard|restore)(?:[/.]|$)) {
    limit_conn api_gateway 4;
    limit_conn api_gateway_address 16;
    limit_conn_status 429;
    access_log /var/log/nginx/access.log api_gateway;

    auth_request /api/v4/relay/verdict;
    auth_request_set $api_gateway_engine_origin $upstream_http_x_engine_origin;
    auth_request_set $api_gateway_engine_path $upstream_http_x_engine_path;
    auth_request_set $api_gateway_relay_token $upstream_http_x_relay_token;
    auth_request_set $api_gateway_user_id $upstream_http_x_etm_user_id;
    auth_request_set $api_gateway_token_id $upstream_http_x_etm_token_id;
    auth_request_set $api_gateway_version $upstream_http_x_etm_version;
    auth_request_set $api_gateway_refusal_status $upstream_http_x_etm_refusal_status;
    auth_request_set $api_gateway_refusal_code $upstream_http_x_etm_refusal_code;
    auth_request_set $api_gateway_refusal_detail $upstream_http_x_etm_refusal_detail;

    error_page 401 403 = @api_gateway_refusal;
    error_page 429 = @api_gateway_throttled;
    error_page 500 = @api_gateway_verdict_failed;
    error_page 502 504 = @api_gateway_engine_unavailable;

    # The engine origin is a variable, so nginx resolves it per request.
    resolver 127.0.0.11 valid=30s ipv6=off;
    proxy_ssl_server_name on;
    proxy_ssl_verify on;
    proxy_ssl_verify_depth 2;
    proxy_ssl_trusted_certificate /etc/nginx/certs/ca/rootCA.pem;
    proxy_connect_timeout 5s;
    # Under the engine front's 60s, so a slow engine is answered here in JSON rather than by the front.
    proxy_read_timeout 55s;

    # Setting any header here drops the http level ones, so Host becomes the engine's own.
    proxy_set_header Authorization $api_gateway_authorization;
    proxy_set_header Cookie "";
    proxy_set_header Proxy "";
    # The engine's Rack::MethodOverride would otherwise turn a POST into a DELETE.
    proxy_set_header X-HTTP-Method-Override "";
    proxy_set_header X-Forwarded-For $proxy_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_pass $api_gateway_engine_address$api_gateway_engine_path$is_args$args;
}

# Neither the verdict nor the refusal renderer is reachable by a client.
location ^~ /api/v4/relay/ {
    internal;
}

# proxy_pass targets the upstream nginx-proxy names after MyETM's host.
location = /api/v4/relay/verdict {
    internal;
    proxy_pass http://myetm.local.energytransitionmodel.com;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Original-URI $request_uri;
    proxy_set_header X-Original-Method $request_method;
    proxy_set_header X-Forwarded-For $proxy_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location @api_gateway_refusal {
    access_log /var/log/nginx/access.log api_gateway;
    rewrite ^ /api/v4/relay/refusal break;
    proxy_pass http://myetm.local.energytransitionmodel.com;
    proxy_pass_request_body off;
    proxy_set_header Content-Length "";
    proxy_set_header Connection "";
    proxy_set_header Authorization "";
    proxy_set_header Host $host;
    proxy_set_header X-Etm-Refusal-Status $api_gateway_refusal_status;
    proxy_set_header X-Etm-Refusal-Code $api_gateway_refusal_code;
    proxy_set_header X-Etm-Refusal-Detail $api_gateway_refusal_detail;
    proxy_set_header X-Forwarded-For $proxy_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

location @api_gateway_throttled {
    access_log /var/log/nginx/access.log api_gateway;
    default_type application/json;
    return 429 '{"errors":[{"status":429,"code":"too_many_requests","detail":"Too many concurrent calls"}]}';
}

location @api_gateway_verdict_failed {
    access_log /var/log/nginx/access.log api_gateway;
    default_type application/json;
    return 500 '{"errors":[{"status":500,"code":"internal_error","detail":"The relay could not give a verdict"}]}';
}

location @api_gateway_engine_unavailable {
    access_log /var/log/nginx/access.log api_gateway;
    default_type application/json;
    return 502 '{"errors":[{"status":502,"code":"engine_unavailable","detail":"The engine did not answer"}]}';
}
