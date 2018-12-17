%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Copyright 2012-2019 Tail-f Systems AB
%%
%% See the file "LICENSE" for information on usage and redistribution
%% of this file, and for a DISCLAIMER OF ALL WARRANTIES.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(lux).

-export([trace_me/4, trace_me/5]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Types

-export_type([filename/0, dirname/0, opts/0, summary/0,
             lineno/0, file_skip/0, file_error/0, no_input/0,
             result/0, run_mode/0]).

-include("lux.hrl").

-type run_mode()   :: list | list_dir | doc | validate | execute.
-type filename()   :: string().
-type dirname()    :: string().
-type opts()       :: [{atom(), term()}].
-type summary()    :: success | skip | warning | fail | error.
-type lineno()     :: string().
-type file_skip()  :: {skip, lux:filename(), string()}.
-type file_error() :: {error, lux:filename(), string()}.
-type no_input()   :: {error, undefined, no_input_files}.
-type result()     :: {ok, lux:filename(), lux:summary(),
                       lux:lineno(), [#warning{}]}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Enable simplified tracing and viewing it as a sequence chart
%% See et:trace_me/5

trace_me(DetailLevel, FromTo, Label, Contents) ->
    %% N.B External call
    ?MODULE:trace_me(DetailLevel, FromTo, FromTo, Label, Contents).

trace_me(_DetailLevel, _From, _To, _Label, _Contents) ->
    hopefully_traced.
