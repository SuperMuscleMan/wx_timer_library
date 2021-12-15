%%%-------------------------------------------------------------------
%%% @author WeiMengHuan
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 23. 三月 2021 20:57
%%%-------------------------------------------------------------------
-module(wx_timer_server).
%%%=======================STATEMENT====================
-description("wx_timer_server").
-copyright('').
-author("wmh, SuperMuscleMan@outlook.com").
-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([set/1, start_timer/0]).

%% gen_server callbacks
-export([init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3]).

-include_lib("wx_log_library/include/wx_log.hrl").

-define(SERVER, ?MODULE).

-define(Timer_Seconds, 100).%% 定时器精度100ms

-record(state, {run_list = []}).

%%%===================================================================
%%% API
%%%===================================================================
set({{_, Key}, MFA}) ->
	gen_server:call(?MODULE, {set, Key, MFA}).
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
	{ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
	gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

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
-spec(init(Args :: term()) ->
	{ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term()} | ignore).
init([]) ->
	erlang:process_flag(trap_exit, true),
	ets:new(?MODULE, [named_table, {keypos, 1}]),
	{ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
		State :: #state{}) ->
	{reply, Reply :: term(), NewState :: #state{}} |
	{reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
	{noreply, NewState :: #state{}} |
	{noreply, NewState :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
	{stop, Reason :: term(), NewState :: #state{}}).
handle_call({set, Key, {M, F, A, Interval, TimeOut}}, _From, State) ->
	ets:insert(?MODULE, {Key, M, F, A, Interval, TimeOut, 0}),
	{reply, ok, State};
handle_call(_Request, _From, State) ->
	{reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
	{noreply, NewState :: #state{}} |
	{noreply, NewState :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: #state{}}).
handle_cast({run, Pid, Key, Expire}, #state{run_list = RunList} = State) ->
	{noreply, State#state{run_list = [{Pid, Key, Expire} | RunList]}};
handle_cast(_Request, State) ->
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
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
	{noreply, NewState :: #state{}} |
	{noreply, NewState :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: #state{}}).
handle_info(timer, #state{run_list = RunList} = State) ->
	Now = wx_time:now_millisec(),
	RunList1 = check_expire(RunList, Now, []),
	ets:foldl(fun handle_timer/2, Now, ?MODULE),
	start_timer(),
	{noreply, State#state{run_list = RunList1}};
handle_info({'DOWN', _, process, _, normal}, State) ->
	{noreply, State};
handle_info(OtherInfo, State) ->
	?ERR({other_info, OtherInfo}),
	{noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
		State :: #state{}) -> term()).
terminate(_Reason, _State) ->
	ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
		Extra :: term()) ->
	{ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%get_data(Key)->
%%	case ets:lookup(?MODULE, Key) of
%%		[D] ->D;
%%		_-> none
%%	end.

set_data(D) ->
	ets:insert(?MODULE, D).


%% 检测过期
check_expire([{Pid, Key, Expire} = H | T], Now, Result) ->
	case is_process_alive(Pid) of
		false ->
			check_expire(T, Now, Result);
		true when Now > Expire ->
			CurStack = process_info(Pid, current_stacktrace),
			erlang:exit(Pid, wx_timer_expire),
			?ERR({wx_timer_expire, {timer_key, Key}, {current_stack, CurStack}}),
			check_expire(T, Now, Result);
		true ->
			check_expire(T, Now, [H | Result])
	end;
check_expire([], _, R) ->
	R.

handle_timer({Key, M, F, A, Interval, TimeOut, 0}, Now) ->
	handle_timer_(Now, Interval, Key, M, F, A, TimeOut),
	Now;
handle_timer({Key, M, F, A, Interval, TimeOut, NextTime}, Now) ->
	case Now > NextTime of
		true ->
			handle_timer_(Now, Interval, Key, M, F, A, TimeOut);
		_ ->
			ok
	end,
	Now.
handle_timer_(Now, Interval, Key, M, F, A, TimeOut) ->
	NowExpire = Now + TimeOut,
	NextTime = Now + Interval,
	erlang:spawn_monitor(
		fun() ->
			%% 当事件进程堆栈大小超过10MB时kill掉10*1024*1024
			erlang:process_flag(max_heap_size, #{size => 16#140000, kill => true,
				error_logger => true}),
			gen_server:cast(?MODULE, {run, self(), Key, NowExpire}),
			handle_(Key, M, F, A, NowExpire)
		end),
	set_data({Key, M, F, A, Interval, TimeOut, NextTime}).
handle_(Key, M, F, A, NowExpire) ->
	try
		?DEBUG({timer, Key, {M, F, A, NowExpire}}),
		M:F(Key, A)
	catch
		_E1:E2:E3 ->
			?ERR({wx_timer_handle, {reason, E2}, {m, M},
				{f, F}, {a, A}, {expire, NowExpire}, E3})
	end.


start_timer() ->
	erlang:send_after(?Timer_Seconds, ?MODULE, timer),
	ok.