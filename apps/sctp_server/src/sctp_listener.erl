%%%-------------------------------------------------------------------
%%% @author vlad <lib.aca55a@gmail.com>
%%% @copyright (C) 2014, vlad
%%% @doc
%%%
%%% @end
%%% Created : 19 Dec 2014 by vlad <lib.aca55a@gmail.com>
%%%-------------------------------------------------------------------
-module(sctp_listener).

-behaviour(gen_server).

%% External API
-export([start_link/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3]).

-include_lib("kernel/include/inet.hrl").
-include_lib("kernel/include/inet_sctp.hrl").

-include_lib("sctp_server/include/sctp_logger.hrl").

%% -define(NOTRACE,true).
-include_lib("eunit_fsm/include/eunit_seq_trace.hrl").


%% Request a specific number of streams just because we can.
-define(SCTP_INIT, #sctp_initmsg{num_ostreams = 5,
                                 max_instreams = 5}).
-define(SCTP_OPTS, [binary, {recbuf,65536}, {reuseaddr, true}, {sctp_initmsg, ?SCTP_INIT}]).


-record(state, {
          listener :: gen_sctp:sctp_socket(),       % Listening socket
          module   :: atom()       % FSM handling module
         }).

%%--------------------------------------------------------------------
%% @spec (Port::integer(), Module) -> {ok, Pid} | {error, Reason}
%
%% @doc Called by a supervisor to start the listening process.
%% @end
%%----------------------------------------------------------------------
start_link(Port, Module) when is_integer(Port), is_atom(Module) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Port, Module], []).

%%%------------------------------------------------------------------------
%%% Callback functions from gen_server
%%%------------------------------------------------------------------------

%%----------------------------------------------------------------------
%% @spec (Port::integer()) -> {ok, State}           |
%%                            {ok, State, Timeout}  |
%%                            ignore                |
%%                            {stop, Reason}
%%
%% @doc Called by gen_server framework at process startup.
%%      Create listening socket.
%% @end
%%----------------------------------------------------------------------
init([Port, Module]) ->
    process_flag(trap_exit, true),
    ?testTraceItit(42, ['receive', print, timestamp, send]),
    ?testTracePrint(42,"listener init"),
    Opts = [{ip, any}, {port, Port}, {active, once} | ?SCTP_OPTS],
    case gen_sctp:open(Opts) of
        {ok, Listen_socket} ->
            %%Create first accepting process
            ok = gen_sctp:listen(Listen_socket, true),
            {ok, #state{listener = Listen_socket,
                        module   = Module}};
        {error, Reason} ->
            {stop, Reason};
        Val ->
            ?ERROR(">> open: ~p", [Val])
    end.

%%-------------------------------------------------------------------------
%% @doc Callback for synchronous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%%-------------------------------------------------------------------------
handle_call(Request, _From, State) ->
    {stop, {unknown_call, Request}, State}.

%%-------------------------------------------------------------------------
%% @doc Callback for asyncrous server calls.  If `{stop, ...}' tuple
%%      is returned, the server is stopped and `terminate/2' is called.
%% @end
%%-------------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%-------------------------------------------------------------------------
%% @spec (Msg, State) ->{noreply, State}          |
%%                      {noreply, State, Timeout} |
%%                      {stop, Reason, State}
%% @doc Callback for messages sent directly to server's mailbox.
%%      If `{stop, ...}' tuple is returned, the server is stopped and
%%      `terminate/2' is called.
%% @end
%% @private
%%-------------------------------------------------------------------------

%% Association established ...
handle_info({sctp, ListSock, FromIP, FromPort,
             {[], #sctp_assoc_change{state = comm_up,
                                     outbound_streams = OS,
                                     inbound_streams = IS,
                                     assoc_id = AssocId}}},
            #state{listener=ListSock, module=Module} = State) ->
    try
        {ok, CliSocket} = gen_sctp:peeloff(ListSock, AssocId),
        {ok, Pid} = sctp_server_app:start_client_peer(),
        gen_sctp:controlling_process(CliSocket, Pid),
        %% Instruct the new FSM that it owns the socket.
        Module:set_socket(Pid, CliSocket, AssocId),

        %% Signal the network driver that we are ready to accept another connection
        inet:setopts(ListSock, [{active, once}]), 

        {noreply, State}
    catch exit:Why ->
        ?ERROR("Error in async accept: ~p.\n", [Why]),
        {stop, Why, State}
    end;

%% Lost association after establishment.
handle_info({sctp, _Sock, RA, _RP, #sctp_assoc_change{} = SAC}, State) ->
    ?ERROR("Lost association after establishment state: ~p assoc: ~p remote: ~p", 
           [SAC#sctp_assoc_change.state, 
            SAC#sctp_assoc_change.assoc_id,
            RA]),
    {noreply, State};
handle_info({sctp, _Sock, _RA, _RP, #sctp_paddr_change{}}, State) ->
    {noreply, State};
handle_info({sctp, _Sock, _RA, _RP, #sctp_pdapi_event{}}, State) ->
    {noreply, State}.

%%-------------------------------------------------------------------------
%% @spec (Reason, State) -> any
%% @doc  Callback executed on server shutdown. It is only invoked if
%%       `process_flag(trap_exit, true)' is set by the server process.
%%       The return value is ignored.
%% @end
%% @private
%%-------------------------------------------------------------------------
terminate(_Reason, State) ->
    gen_sctp:close(State#state.listener),
    ok.

%%-------------------------------------------------------------------------
%% @spec (OldVsn, State, Extra) -> {ok, NewState}
%% @doc  Convert process state when code is changed.
%% @end
%% @private
%%-------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%------------------------------------------------------------------------
%%% Internal functions
%%%------------------------------------------------------------------------

