%%%-------------------------------------------------------------------
%%% @author vlad <lib.aca55a@gmail.com>
%%% @copyright (C) 2014, vlad
%%% @doc
%%%
%%% @end
%%% Created : 19 Dec 2014 by vlad <lib.aca55a@gmail.com>
%%%-------------------------------------------------------------------
-module(sctp_connector_sup).
 
-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

-define(MAX_RESTART,    5).
-define(MAX_TIME,      60).
 
start_link(Module) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [Module]).

init([Module]) ->
    {ok,
        {_SupFlags = {simple_one_for_one, ?MAX_RESTART, ?MAX_TIME},
            [
              % SCTP Server peer
              {   undefined,                               % Id       = internal id
                  {sctp_connector,start_link,[Module]}, % StartFun = {M, F, A}

                  %% {Module,start_link,[]},                  % StartFun = {M, F, A}
                  temporary,                               % Restart  = permanent | transient | temporary
                  2000,                                    % Shutdown = brutal_kill | int() >= 0 | infinity
                  worker,                                  % Type     = worker | supervisor
                  []                                       % Modules  = [Module] | dynamic
              }
            ]
        }
    }.

%%%===================================================================
%%% Internal functions
%%%===================================================================
 
