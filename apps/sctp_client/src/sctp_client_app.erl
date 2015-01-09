-module(sctp_client_app).

-behaviour(application).

%% Internal API
-export([start_connector/0, 
         start_server_peer/0]).

%% External API
-export([connect/2, disconnect/1]).

%% Application callbacks
-export([start/2, stop/1]).


%% A startup function for spawning new client connection.
start_connector() ->
    supervisor:start_child(sctp_connector_sup, []).

%% A startup function for spawning new server connection handling FSM.
%% To be called by the SCTP listener process.
start_server_peer() ->
    supervisor:start_child(sctp_server_peer_sup, []).


-spec connect(inet:ip_address(),inet:port_number()) -> pid().
connect(Host, Port)->
    {ok, Pid} = sctp_client_app:start_connector(),
    ok = sctp_connector:connect(Pid, Host, Port),
    Pid.

-spec disconnect(pid()) -> ok.
disconnect(Pid) when is_pid(Pid) ->
    sctp_connector:disconnect(Pid).

%% ===================================================================
%% Application callbacks
%% ===================================================================

-spec start(any(), any()) -> {ok, pid()}.
start(_StartType, _StartArgs) ->
    sctp_client_sup:start_link(sctp_client_fsm).

-spec stop(any()) -> ok.
stop(_State) ->
    ok.
