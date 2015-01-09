
-module(sctp_client_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(MAX_RESTART,    5).
-define(MAX_TIME,      60).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(Module) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Module]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([Module]) ->
    {ok,
     {_SupFlags = {one_for_one, ?MAX_RESTART, ?MAX_TIME},
      [
       %% SCTP Connector supervisor
       {   sctp_connector_sup,
           {sctp_connector_sup,start_link, [Module]},
           permanent,                               % Restart  = permanent | transient | temporary
           infinity,                                % Shutdown = brutal_kill | int() >= 0 | infinity
           supervisor,                              % Type     = worker | supervisor
           []                                       % Modules  = [Module] | dynamic
       },
       %% Client instance supervisor
       {   sctp_server_peer_sup,
           {sctp_server_peer_sup,start_link, [Module]},
           permanent,                               % Restart  = permanent | transient | temporary
           infinity,                                % Shutdown = brutal_kill | int() >= 0 | infinity
           supervisor,                              % Type     = worker | supervisor
           []                                       % Modules  = [Module] | dynamic
       }
      ]
     }
    }.

