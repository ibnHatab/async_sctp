%%%-------------------------------------------------------------------
%%% @author vlad <lib.aca55a@gmail.com>
%%% @copyright (C) 2014, vlad
%%% @doc
%%%
%%% @end
%%% Created : 19 Dec 2014 by vlad <lib.aca55a@gmail.com>
%%%-------------------------------------------------------------------
-module(sctp_server_app).

-behaviour(application).

%% Internal API
-export([start_client_peer/0]).

%% Application callbacks
-export([start/2, stop/1]).

-define(DEF_PORT, 3333).

%% To be called by the SCTP connector process.
start_client_peer() ->
    supervisor:start_child(sctp_client_peer_sup, []).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    ListenPort = get_app_env(listen_port, ?DEF_PORT),
    sctp_server_sup:start_link(ListenPort, sctp_echo_fsm).


stop(_State) ->
    ok.

%%----------------------------------------------------------------------
%% Internal functions
%%----------------------------------------------------------------------
get_app_env(Opt, Default) ->
    case application:get_env(application:get_application(), Opt) of
    {ok, Val} -> Val;
    _ ->
        case init:get_argument(Opt) of
        [[Val | _]] -> Val;
        error       -> Default
        end
    end.
