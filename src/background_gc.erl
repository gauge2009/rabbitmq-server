%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2012 VMware, Inc.  All rights reserved.
%%

-module(background_gc).

-behaviour(gen_server2).

-export([start_link/0]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(HIBERNATE_AFTER_MIN, 1000).
-define(DESIRED_HIBERNATE, 10000).

-define(MAX_RATIO, 0.01).
-define(IDEAL_INTERVAL, 60000).
-define(MIN_BYTES, 50000).

-record(state, {last_interval}).

%%----------------------------------------------------------------------------

start_link() ->
    gen_server2:start_link({local, ?MODULE}, ?MODULE, [],
                           [{timeout, infinity}]).

%%----------------------------------------------------------------------------

init([]) ->
    {ok, run_gc(#state{last_interval = ?IDEAL_INTERVAL}), hibernate,
     {backoff, ?HIBERNATE_AFTER_MIN, ?HIBERNATE_AFTER_MIN, ?DESIRED_HIBERNATE}}.

handle_call(Msg, _From, State) ->
    {stop, {unexpected_call, Msg}, State}.

handle_cast(Msg, State) ->
    {stop, {unexpected_cast, Msg}, State}.

handle_info(run_gc, State) ->
    {noreply, run_gc(State)};

handle_info(Msg, State) ->
    {stop, {unexpected_info, Msg}, State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, State) ->
    State.

%%----------------------------------------------------------------------------

run_gc(State = #state{last_interval = LastInterval}) ->
    {ok, Interval} = rabbit_misc:interval_operation(
                       fun do_gc/0, ?MAX_RATIO, ?IDEAL_INTERVAL, LastInterval),
    erlang:send_after(Interval, self(), run_gc),
    State#state{last_interval = Interval}.

do_gc() ->
    [garbage_collect(P) || P <- processes(),
                           {status, waiting} == process_info(P, status)],
    ok.
