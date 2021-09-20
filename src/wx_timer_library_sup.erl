%%%-------------------------------------------------------------------
%% @doc wx_timer_library top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(wx_timer_library_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 3,
                 period => 180},
    ChildSpecs = [
		#{
			id => wx_timer_server,
			start => {wx_timer_server, start_link, []},
			restart => permanent,
			shutdown => infinity,
			type => worker,
			modules => [wx_timer_server]
		}
	],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions