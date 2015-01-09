%%% @author vlad <lib.aca55a@gmail.com>
%%% @copyright (C) 2014, vlad
%%% @doc
%%%
%%% @end
%%% Created : 19 Dec 2014 by vlad <lib.aca55a@gmail.com>

-module(sctp_server_tests).
 
-include_lib("kernel/include/inet.hrl").
-include_lib("kernel/include/inet_sctp.hrl").

-include_lib("eunit/include/eunit.hrl").

-include_lib("eunit_fsm/include/eunit_seq_trace.hrl").
  
%% Receive a message.
-define(RECV(Pat, Ret), receive Pat -> Ret end).
-define(RECV(Pat), ?RECV(Pat, now())).
 
-define(DEF_HOST, {127,0,0,1}).
-define(DEF_PORT,    3333).
-define(SCTP(Sock, Data), {sctp, Sock, _, _, Data}).

sctp_server_setup_test_() ->
   {timeout, 3000,
     {setup,
      fun setup/0, 
      fun teardown/1,
         [{"Start/stop SCTP server common logic", fun logic/0}]}}.

logic() ->
    ?assertEqual(ok, application:start(sctp_server)),
    ?testTraceItit(44, ['receive', print, timestamp, send]),
    ?testTracePrint(44,"logic init"),

    {ok,S} = gen_sctp:open(), 
    {ok,Assoc} = gen_sctp:connect 
                   (S, ?DEF_HOST, ?DEF_PORT, [{sctp_initmsg,#sctp_initmsg{num_ostreams=5}}]),
    ?debugFmt("Connection Successful, Assoc=~p~n", [Assoc]),
      
    ?debugVal(gen_sctp:send(S, Assoc, 0, <<"hello">>)),
    
    {ok,{_,_,[#sctp_sndrcvinfo{}], Bin}} = gen_sctp:recv(S,1000),

    ?assertEqual(<<"hello">>, Bin). 

setup() ->
    ensure_started(sasl), 
    ensure_started(compiler),
    ensure_started(syntax_tools), 
    ensure_started(lager),
    %% SPAWN TRACES
    Pid = spawn(eunit_seq_trace,tracer,[]),
    seq_trace:set_system_tracer(Pid), % set Pid as the system tracer
    Pid.
 
teardown(TracerPid) ->
     application:stop(sctp_server),
    exit(TracerPid, ok),
    ok.

ensure_started(App) ->
    case application:start(App) of
        ok -> ok;
        {error, {already_started, App}} -> ok
    end.
 
