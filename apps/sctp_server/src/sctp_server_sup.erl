
-module(sctp_server_sup).

-behaviour(supervisor).

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

-define(MAX_RESTART,    5).
-define(MAX_TIME,      60).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(ListenPort, Module) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [ListenPort, Module]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([Port, Module]) ->
    {ok,
     {_SupFlags = {one_for_one, ?MAX_RESTART, ?MAX_TIME},
      [
                                                % SCTP Listener
       {   sctp_server_sup,                          % Id       = internal id
           {sctp_listener,start_link,[Port,Module]}, % StartFun = {M, F, A}
           permanent,                               % Restart  = permanent | transient | temporary
           2000,                                    % Shutdown = brutal_kill | int() >= 0 | infinity
           worker,                                  % Type     = worker | supervisor
           [sctp_listener]                           % Modules  = [Module] | dynamic
       },
                                                % Client instance supervisor
       {   sctp_client_peer_sup,
           {sctp_client_peer_sup,start_link, [Module]},
           permanent,                               % Restart  = permanent | transient | temporary
           infinity,                                % Shutdown = brutal_kill | int() >= 0 | infinity
           supervisor,                              % Type     = worker | supervisor
           []                                       % Modules  = [Module] | dynamic
       }
      ]
     }
    }.
