%%% @author vlad <lib.aca55a@gmail.com>
%%% @copyright (C) 2014, vlad
%%% @doc
%%%
%%% @end
%%% Created : 19 Dec 2014 by vlad <lib.aca55a@gmail.com>

-module(sctp_client_tests).

-include_lib("kernel/include/inet.hrl").
-include_lib("kernel/include/inet_sctp.hrl").

-include_lib("eunit_fsm/include/eunit_fsm.hrl").
-include_lib("eunit_fsm/include/eunit_seq_trace.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(DEF_HOST, {127,0,0,1}).
-define(DEF_PORT, 3333).

sctp_client_test_() ->
   {timeout, 10000,
    {setup,
     fun setup/0,
     fun teardown/1,
     [
      ?_fsm_test(whereis(sctp_listener), "Start  server and client",
                 [
                  {call, application, start, [sctp_server], ok}
                 ,{srvdata, match, [fun erlang:is_port/1 ,sctp_echo_fsm]}
                 ,{call, application, start, [sctp_client], ok}
                 ]),  
      {"Setup connector", 
       {setup,
        fun () -> {ok, Pid} = sctp_client_app:start_connector(), 
                  Pid end,
        fun (_) -> ok end,
        {with, 
         [
          ?_with_fsm_test("Connect/disconnect", 
                          [
                           {srvdata, match, [fun erlang:is_port/1,undefined,undefined,undefined,
                                             sctp_client_fsm,undefined]}
                          ,{callwith, sctp_connector, connect, [?DEF_HOST,?DEF_PORT,{4,2000,2.0}], ok}
                          ,{sleep, 1000}
                          ,{srvdata, match, [undefined,any,any,fun erlang:is_pid/1,sctp_client_fsm,
                                             {retry_opts,4,2000,2.0,1}]}                            
                          ,{callwith, sctp_connector, disconnect, [], ok}
                          ,{sleep, 500} 
                          ])  
         ]} 
       }}, 
      ?_test(?assertEqual(proplists:lookup(active, supervisor:count_children(sctp_client_peer_sup)), 
                          {active, 0})),
      ?_fsm_test(whereis(sctp_client_peer_sup), "Stop client server", 
                 [
                  {call, application, stop, [sctp_client], ok}
                  %% ,{srvdata, show}
                  %% {call, application, start, [sctp_client], ok}
                 ])
     ]
    }}.
 
 
sctp_client_setup_test_no() ->
   {timeout, 3000,
     {setup,
      fun setup/0,
      fun teardown/1,
         [{"Start/stop SCTP client common logic", fun logic/0}]}}.

 
logic() ->
    ?assertEqual(ok, application:start(sctp_server)),
    case get_status(whereis(sctp_listener), "State") of
        {state,Port,sctp_echo_fsm} when is_port(Port) ->
            ?assert(is_port(Port))
    end,
    ?assertEqual(ok, application:start(sctp_client)),

    {ok, ConnPid} = sctp_client_app:start_connector(),
    case get_status(ConnPid, "State") of
        {state, _,undefined,undefined,sctp_client_fsm} -> ok
    end,
    ok = sctp_connector:connect(ConnPid, ?DEF_HOST, ?DEF_PORT),
    timer:sleep(1000),
    HndPid = case get_status(ConnPid, "State") of
                 {state,_,_,Val,sctp_client_fsm} -> Val
             end,
    case get_status(HndPid, "StateName") of
        'WAIT_FOR_DATA' -> ok
    end,

    %% ?assertEqual(ok, application:start(sctp_client)),
    %% Ref = sctp_connector:connect(Pid, ?DEF_HOST, ?DEF_PORT),
    timer:sleep(1000),
    application:stop(sctp_server),
    ok.


setup() ->
    ensure_started(sasl),
    ensure_started(compiler),
    ensure_started(syntax_tools),
    ensure_started(lager),
    %% SPAWN TRACES
    Pid = spawn(eunit_seq_trace,tracer,[]),
    seq_trace:set_system_tracer(Pid), % set Pid as the system tracer
    ?testTraceItit(44, ['receive', print, timestamp, send]),
    ?testTracePrint(44,"sctp_client_tests setup"),
    Pid.

teardown(Pid) ->
    catch application:stop(sctp_client),
    catch application:stop(sctp_server),
    ?testTracePrint(44,"sctp_client_tests teardown"),
    exit(Pid, ok),
    ok.

get_status(Pid, Which) ->
    {status, Pid, _Mod, List} = sys:get_status(Pid),
    AllData = lists:flatten([ X || {data, X} <- lists:last(List)]),
    proplists:get_value(Which, AllData).

ensure_started(App) ->
    case application:start(App) of
        ok -> ok;
        {error, {already_started, App}} -> ok
    end.
