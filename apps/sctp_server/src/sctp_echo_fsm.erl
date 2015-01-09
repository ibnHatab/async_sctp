%%%-------------------------------------------------------------------
%%% @author vlad <lib.aca55a@gmail.com>
%%% @copyright (C) 2014, vlad
%%% @doc
%%%
%%% @end
%%% Created : 19 Dec 2014 by vlad <lib.aca55a@gmail.com>
%%%-------------------------------------------------------------------
-module(sctp_echo_fsm).

-behaviour(gen_fsm).

-export([start_link/0, set_socket/3]).

%% gen_fsm callbacks
-export([init/1, handle_event/3,
         handle_sync_event/4, handle_info/3, terminate/3, code_change/4]).

-include_lib("kernel/include/inet.hrl").
-include_lib("kernel/include/inet_sctp.hrl").
-include_lib("sctp_server/include/sctp_logger.hrl").

%% -define(NOTRACE,true).
-include_lib("eunit_fsm/include/eunit_seq_trace.hrl").

%% FSM States
-export([
    'WAIT_FOR_SOCKET'/2,
    'WAIT_FOR_DATA'/2
]).

-record(state, {
          socket,    % client socket
          assoc,
          addr       % client address
         }).

-define(TIMEOUT, 120000).

%%%------------------------------------------------------------------------
%%% API
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% @spec (Socket) -> {ok,Pid} | ignore | {error,Error}
%% @doc To be called by the supervisor in order to start the server.
%%      If init/1 fails with Reason, the function returns {error,Reason}.
%%      If init/1 returns {stop,Reason} or ignore, the process is
%%      terminated and the function returns {error,Reason} or ignore,
%%      respectively.
%% @end
%%-------------------------------------------------------------------------
start_link() ->
    gen_fsm:start_link(?MODULE, [], []).

set_socket(Pid, Socket, AssocId) when is_pid(Pid), is_port(Socket), is_integer(AssocId)->
    gen_fsm:send_event(Pid, {socket_ready, Socket, AssocId}).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

%%-------------------------------------------------------------------------
%% Func: init/1
%% Returns: {ok, StateName, StateData}          |
%%          {ok, StateName, StateData, Timeout} |
%%          ignore                              |
%%          {stop, StopReason}
%% @private
%%-------------------------------------------------------------------------
init([]) ->
    process_flag(trap_exit, true),
    ?testTraceItit(43, ['receive', print, timestamp, send]),
    ?testTracePrint(43,"handle init"),
    {ok, 'WAIT_FOR_SOCKET', #state{}}.

%%-------------------------------------------------------------------------
%% Func: StateName/2
%% Returns: {next_state, NextStateName, NextStateData}          |
%%          {next_state, NextStateName, NextStateData, Timeout} |
%%          {stop, Reason, NewStateData}
%% @private
%%-------------------------------------------------------------------------
'WAIT_FOR_SOCKET'({socket_ready, Socket, AssocId}, State) when is_port(Socket) ->
    % Now we own the socket
    ?INFO("Now we own the socket: ~p",[Socket]),
    inet:setopts(Socket, [{active, once}, binary]),
    {ok, {IP, _Port}} = inet:peername(Socket),
    {next_state, 'WAIT_FOR_DATA', State#state{socket=Socket, assoc=AssocId, addr=IP}, ?TIMEOUT};
'WAIT_FOR_SOCKET'(Other, State) ->
    ?ERROR("State: 'WAIT_FOR_SOCKET'. Unexpected message: ~p\n", [Other]),
    %% Allow to receive async messages
    {next_state, 'WAIT_FOR_SOCKET', State}.

%% Notification event coming from client
'WAIT_FOR_DATA'({data, Data}, #state{socket=S, assoc=A} = State) ->
    ok = gen_sctp:send(S, A, 0, Data),
    {next_state, 'WAIT_FOR_DATA', State, ?TIMEOUT};

'WAIT_FOR_DATA'(timeout, State) ->
    ?ERROR("~p Client connection timeout - closing.\n", [self()]),
    {stop, normal, State};

'WAIT_FOR_DATA'(Data, State) ->
    ?DEBUG("~p Ignoring data: ~p\n", [self(), Data]),
    {next_state, 'WAIT_FOR_DATA', State, ?TIMEOUT}.

%%-------------------------------------------------------------------------
%% Func: handle_event/3
%%-------------------------------------------------------------------------
handle_event(Event, StateName, StateData) ->
    {stop, {StateName, undefined_event, Event}, StateData}.

%%-------------------------------------------------------------------------
%% Func: handle_sync_event/4
%%-------------------------------------------------------------------------
handle_sync_event(Event, _From, StateName, StateData) ->
    {stop, {StateName, undefined_event, Event}, StateData}.

%%-------------------------------------------------------------------------
%% Func: handle_info/3
%%-------------------------------------------------------------------------
handle_info({sctp, _CliSock, _FromIP, _FromPort,
             {[#sctp_sndrcvinfo{stream = _Id}], Bin}}, StateName,
            #state{socket=Socket} = StateData) ->
    %% Flow control: enable forwarding of next SCTP message
    inet:setopts(Socket, [{active, once}]),
    ?MODULE:StateName({data, Bin}, StateData);
handle_info({sctp, _Sock, _RA, _RP,
             {[], #sctp_assoc_change{state = comm_lost}}},
            _StateName,
            #state{socket=Socket, addr=Addr} = StateData) ->
    ?INFO("~p Communication ~p lost.\n", [self(), Addr]),
    {stop, normal, StateData};
handle_info({sctp, _CliSock, _FromIP, _FromPort,
            {_, #sctp_shutdown_event{assoc_id = _Id}}},
            _StateName,
            #state{socket=Socket, addr=Addr} = StateData) ->
    ?INFO("~p Client ~p disconnected.\n", [self(), Addr]),
    {stop, normal, StateData};
handle_info({sctp, _Sock, _RA, _RP, {_, #sctp_pdapi_event{}}}, StateName, StateData) ->
    inet:setopts(StateData#state.socket, [{active, once}, binary]),
    {next_state, StateName, StateData};
handle_info({sctp, _Sock, _RA, _RP, {_, #sctp_paddr_change{}}}, StateName, StateData) ->
    inet:setopts(StateData#state.socket, [{active, once}, binary]),
    {next_state, StateName, StateData};
handle_info(Data, StateName, StateData) ->
    ?ERROR("handle_info. Unexpected message: ~p\n", [Data]),
    inet:setopts(StateData#state.socket, [{active, once}, binary]),
    {noreply, StateName, StateData}.

    
%%-------------------------------------------------------------------------
%% Func: terminate/3
%% Purpose: Shutdown the fsm
%% Returns: any
%% @private
%%-------------------------------------------------------------------------
terminate(_Reason, _StateName, #state{socket=Socket}) ->
    (catch gen_sctp:close(Socket)), 
    ok.

%%-------------------------------------------------------------------------
%% Func: code_change/4
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState, NewStateData}
%% @private
%%-------------------------------------------------------------------------
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.
