%%%-------------------------------------------------------------------
%%% @author vlad <lib.aca55a@gmail.com>
%%% @copyright (C) 2015, vlad
%%% @doc
%%%
%%% @end
%%% Created :  2 Jan 2015 by vlad <lib.aca55a@gmail.com>
%%%-------------------------------------------------------------------
-module(sctp_connector).

-behaviour(gen_server).

%% API
-export([start_link/1, connect/3, connect/4, disconnect/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include_lib("kernel/include/inet.hrl").
-include_lib("kernel/include/inet_sctp.hrl").
-include_lib("sctp_client/include/sctp_logger.hrl").

%% -define(TEST,true).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.
-export_records([state]).

-define(SERVER, ?MODULE).

-define(CONNECTION_TIMEOUT, 10000).
-define(TRIES, 4).
-define(DELAY, 2000).
-define(BACKOFF, 2.0).

%% Request a specific number of streams just because we can.
-define(SCTP_INIT, #sctp_initmsg{num_ostreams = 2,
                                 max_instreams = 2}).
-define(SCTP_OPTS, [binary, {recbuf,65536}, {reuseaddr, true}, {sctp_initmsg, ?SCTP_INIT}]).

 % Retry options {TRIES, DELAY, BACKOFF, Retry}
-record(retry_opts, {
          tries   :: non_neg_integer(),
          delay   :: pos_integer(), 
          backoff :: number(),
          retry   :: non_neg_integer()
         }).
-record(state, {
          connector :: gen_sctp:sctp_socket(),  % Connector socket
          ip        :: inet:ip_address(),       % Connect to host
          port      :: inet:port_number(),      % On port
          worker    :: pid(),                   % Current handling process
          module    :: atom(),                  % Handling module
          opts      :: #retry_opts{}            % Retry options
         }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
-spec start_link(atom()) -> {ok, pid()}.
start_link(Module) when is_atom(Module) ->
    gen_server:start_link(?MODULE, [Module], []).

%%--------------------------------------------------------------------
%% @doc
%% Attmpt peer connection
%% @end
%%--------------------------------------------------------------------
-spec connect(pid(),inet:ip_address(),inet:port_number(), Options) -> {ok, pid()} when 
      Options :: {non_neg_integer(), pos_integer(), number() }.
connect(Pid, IP, Port, {Tries,Delay,Backoff}) when is_integer(Port) ->
    gen_server:cast(Pid, {connect, IP, Port, #retry_opts{tries=Tries,
                                                         delay=Delay,
                                                         backoff=Backoff,
                                                         retry=0}}).

-spec connect(pid(),inet:ip_address(),inet:port_number()) -> {ok, pid()}.
connect(Pid, IP, Port) when is_integer(Port) ->
    connect(Pid, IP, Port, {?TRIES, ?DELAY, ?BACKOFF}).

%%--------------------------------------------------------------------
%% @doc
%% Disconnect
%% @end
%%--------------------------------------------------------------------
-spec disconnect(pid()) -> ok.
disconnect(Pid) when is_pid(Pid) ->
    gen_server:cast(Pid, disconnect).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Module]) ->
    process_flag(trap_exit, true),              % Make suppervisor polite
    %%Create connecting socket
    case gen_sctp:open() of
        {ok, ConnectSocket} ->
            {ok, #state{connector=ConnectSocket,
                        module=Module}};
        {error, Reason} ->
            {stop, Reason}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({connect, IP, Port, Options},
            State=#state{connector=ConnectSocket}) ->
    ?INFO("Connecting to ~p:~p",[IP,Port]),
    case schedule(connect, Options) of
        {ok, O} -> 
            SctpOpts = [{active, once} | ?SCTP_OPTS],
            ok = gen_sctp:connect_init(ConnectSocket, IP, Port, SctpOpts),%, ?CONNECTION_TIMEOUT),
            {noreply, State#state{ip=IP,port=Port,opts=O}};
        {error, Reason} -> {stop, Reason, State}
    end;
handle_cast(disconnect, #state{worker=Pid} = State) when is_pid(Pid) ->
    ?WARNING("disconnect:  ~p",[State]),
    exit(Pid, normal),
    {stop, normal, State};
handle_cast(disconnect, State) ->    
    {stop, normal, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({sctp, _Sock, _RA, _RP,
             {[], #sctp_assoc_change{state = comm_up,
                                     assoc_id = AssocId}}},
            #state{connector=ConnectorSock, module=Module} = State) ->
        {ok, Pid} = sctp_client_app:start_server_peer(),
        link(Pid),
        gen_sctp:controlling_process(ConnectorSock, Pid),
        %% Instruct the new FSM that it owns the socket.
        Module:set_socket(Pid, ConnectorSock, AssocId),
        {noreply, State#state{connector=undefined,worker = Pid}};
handle_info({sctp, _Sock, _RA, _RP,
             {[], #sctp_assoc_change{state = cant_assoc}}},
            State=#state{connector=ConnectorSock,ip=IP,opts=Opts}) ->
    ?WARNING("~p Can't Assoc: ~p.\n", [self(),IP]),
    case schedule(cant_assoc, Opts) of
        {wait, O, Timeout} ->
            {ok, Ref} =
                timer:send_after(Timeout, self(),
                                 {reconnect, Timeout}),
            inet:setopts(ConnectorSock, [{active, once}, binary]),
            {noreply, State#state{opts=O}};
        {error, Reason} -> 
            ?ERROR("Can't Assoc: ~p with ~p.\n", [IP, Reason]),
            {stop, normal, State}
    end;
%% Connection timeout
handle_info({reconnect, Timeout}, State=#state{connector=ConnectorSock,ip=IP,port=Port,opts=Opts}) ->
    ?WARNING("Reconnecting: ~p.\n", [Timeout]),    
    case schedule(connect, Opts) of
        {ok, O} ->
            SctpOpts = [{active, once} | ?SCTP_OPTS],
            ok = gen_sctp:connect_init(ConnectorSock, IP, Port, SctpOpts),%, ?CONNECTION_TIMEOUT),
            inet:setopts(ConnectorSock, [{active, once}, binary]),
            {noreply, State#state{opts=O}};
        {error, Reason} -> 
            ?ERROR("Reconnecting: ~p.\n", [Reason]),                
            {stop, Reason, State}
    end;
%% peer worker exited and need to be restarted
handle_info({'EXIT',Pid,_Reason}, State=#state{opts=Opts}) when is_pid(Pid)->
    ?WARNING("Peer worker exited: ~p in state: ~p.\n", [Pid, State]),
    case gen_sctp:open() of
        {ok, ConnectSocket} ->
            handle_info({reconnect, infinity}, State#state{connector=ConnectSocket,
                                                           worker=undefined,
                                                           opts=Opts#retry_opts{retry=0}});
        {error, Reason} ->
            {stop, Reason}
    end;
handle_info(_Info, State) ->
    ?ERROR(">> Unhandled: '~p'' in state: ~p.\n", [_Info, State]),
    {noreply, State}.



%%--------------------------------------------------------------------
%% @private
%% @spec terminate(Reason, State) -> void()
%%--------------------------------------------------------------------
terminate(_Reason, State) ->   
    gen_sctp:close(State#state.connector),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% Retries a connection until it succeed.
%% delay sets the initial delay in miliseconds, and backoff sets the factor by which
%% the delay should lengthen after each failure. backoff must be greater than 1,
%% or else it isn't really a backoff. tries must be at least 0, and delay
%% greater than 0.
%%--------------------------------------------------------------------
-spec schedule(connect | cant_assoc | timeout, #retry_opts{}) -> 
                      {ok, #retry_opts{}} |
                      {wait, #retry_opts{}, timeout()} |
                      {error, term()}.
schedule(connect, #retry_opts{tries=Tries,retry=Tries}) ->   
    {error, no_more_retry};
schedule(cant_assoc, #retry_opts{tries=Tries,retry=Tries}) ->   
    {error, no_more_retry};
schedule(connect, Opts=#retry_opts{retry=Retry}) ->
    {ok, Opts#retry_opts{retry=Retry+1}};
schedule(cant_assoc, Opts=#retry_opts{delay=D,backoff=B,retry=Retry}) ->
    Timeout = round(D * math:pow(B,Retry)),
    {wait, Opts, Timeout}.


-ifdef(TEST).

schedule_test_() ->
    {"schedule test",
     ?_test(
        begin
            Assert = [ %% tries,delay,backoff,retry
                       {connect, {retry_opts, 2,3,4,2}, {error, no_more_retry}}
                       %% connect two times
                     , {connect, {retry_opts, 2,3,4,0}, {ok, {retry_opts, 2,3,4,1}}}
                     , {cant_assoc, {retry_opts, 2,3,4,1}, {wait, {retry_opts, 2,3,4,1}, 3*4}}
                     , {connect, {retry_opts, 2,3,4,1}, {ok, {retry_opts, 2,3,4,2}}}
                     , {cant_assoc, {retry_opts, 2,3,4,2}, {error, no_more_retry}}
                     ],
            [begin  
                 ?debugFmt(">> ~p ~p ~p",[Event,Opts,Expected]),
                 Result = schedule(Event,Opts),
                 ?assertEqual(Expected,Result)
             end || {Event,Opts,Expected} <- Assert],
            ok
        end)    
    }.

-endif.
