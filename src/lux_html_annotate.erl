%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Copyright 2012-2019 Tail-f Systems AB
%%
%% See the file "LICENSE" for information on usage and redistribution
%% of this file, and for a DISCLAIMER OF ALL WARRANTIES.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(lux_html_annotate).

-export([generate/4]).
-import(lux_html_utils, [html_table_td/3, html_td/4]).

-include("lux.hrl").

-record(astate,
        {run_dir,
         run_log_dir,
         new_log_dir,
         suite_log_dir,
         log_file,
         script_file,
         case_prefix,
         start_time,
         end_time,
         html,
         opts}).

-record(file,
        {script,
         script_comps,
         orig_script,
         all_lines
        }).

-record(code_html,
        {script_comps,
         lineno,
         cmd_stack,
         lines
        }).

-record(event_html,
        {script_comps,
         lineno,
         cmd_stack,
         op,
         shell,
         data}).

-record(body_html,
        {script,
         orig_script,
         cmd_stack,
         lineno,
         lines}).

generate(IsRecursive, LogFile, SuiteLogDir, Opts) ->
    WWW = undefined,
    {Res, NewWWW} = do_generate(IsRecursive, LogFile, SuiteLogDir, WWW, Opts),
    lux_utils:stop_app(NewWWW),
    Res.

do_generate(IsRecursive, LogFile, SuiteLogDir, WWW, Opts)
  when is_list(LogFile), is_list(SuiteLogDir) ->
    A = init_astate(LogFile, SuiteLogDir, Opts),
    AbsLogFile = A#astate.log_file,
    IsEventLog = lists:suffix(?CASE_EVENT_LOG, AbsLogFile),
    {Res, NewWWW} =
        case IsEventLog of
            true  -> annotate_event_log(A, WWW);
            false -> annotate_summary_log(IsRecursive, A, WWW)
        end,
    NewRes =
        case Res of
            {ok, "", Html} ->
                lux_html_utils:safe_write_file(AbsLogFile ++ ".html", Html);
            {ok, Csv, Html} ->
                lux_html_utils:safe_write_file(AbsLogFile ++ ".csv", Csv),
                lux_html_utils:safe_write_file(AbsLogFile ++ ".html", Html);
            {error, _File, _ReasonStr} = Error ->
                Error
        end,
    {NewRes, NewWWW}.

init_astate(LogFile, SuiteLogDir, Opts) ->
    AbsLogFile = lux_utils:normalize_filename(LogFile),
    LogDir = filename:dirname(AbsLogFile),
    CasePrefix = lux_utils:pick_opt(case_prefix, Opts, ""),
    Html = lux_utils:pick_opt(html, Opts, enable),
    #astate{new_log_dir = LogDir,
            log_file = AbsLogFile,
            suite_log_dir = SuiteLogDir,
            case_prefix = CasePrefix,
            html = Html,
            opts = Opts}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Annotate a summary log and all its event logs

annotate_summary_log(IsRecursive, #astate{log_file=AbsSummaryLog} = A0, WWW)
  when is_list(AbsSummaryLog) ->
    {ParseRes, NewWWW} = lux_log:parse_summary_log(AbsSummaryLog, WWW),
    case ParseRes of
        {ok, Result, Groups, ConfigSection, _FileInfo, EventLogs} ->
            ConfigBins = binary:split(ConfigSection, <<"\n">>, [global]),
            ConfigProps = lux_log:split_config(ConfigBins),
            RunDir = pick_run_dir(ConfigProps),
            RunLogDir = pick_log_dir(ConfigProps),
            StartTime = pick_time_prop(<<"start time">>, ConfigProps),
            EndTime = pick_time_prop(<<"end time">>, ConfigProps),
            A = A0#astate{run_dir = RunDir,
                          run_log_dir = RunLogDir,
                          start_time = StartTime,
                          end_time = EndTime},
            Html = html_groups(A, AbsSummaryLog, Result,
                               Groups, ConfigSection),
            SuiteLogDir = filename:dirname(AbsSummaryLog),
            case IsRecursive of
                true ->
                    O = A#astate.opts,
                    AnnotateEventLog =
                        fun(EventLog0, W) ->
                                RelEventLog =
                                    drop_run_log_prefix(A, EventLog0),
                                EventLog = lux_utils:join(SuiteLogDir,
                                                          RelEventLog),
                                {GenRes, W2} =
                                    do_generate(IsRecursive,
                                                EventLog,
                                                A#astate.suite_log_dir,
                                                W,
                                                O),
                                case GenRes of
                                    {ok, _} = ValRes ->
                                        ValRes;
                                    {error, _, Reason} ->
                                        io:format("ERROR in ~s\n\~p\n",
                                                  [EventLog, Reason])
                                end,
                                W2
                        end,
                    NewWWW2 = lists:foldl(AnnotateEventLog, NewWWW, EventLogs),
                    NewWWW2 = NewWWW; % assert
                false ->
                    NewWWW
            end,
            {{ok, "", Html}, NewWWW};
        {error, _File, _Reason} = Error ->
            {Error, WWW}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Return summary log as HTML

html_groups(A, SummaryLog, Result, Groups, ConfigSection)
  when is_list(SummaryLog) ->
    Dir = filename:basename(filename:dirname(SummaryLog)),
    RelSummaryLog = drop_new_log_prefix(A, SummaryLog),
    RelResultLog = ?SUITE_RESULT_LOG,
    RelConfigLog = ?SUITE_CONFIG_LOG,
    RelTapLog = ?CASE_TAP_LOG,
    IsTmp = lux_log:is_temporary(SummaryLog),
    LogFun =
        fun(L, S) ->
                ["    <td><strong>",
                 lux_html_utils:html_href("", L, S, "text/plain"),
                 "</strong></td>\n"]
        end,
    [
     lux_html_utils:html_header(["Lux summary log (", Dir, ")"]),
     "<table border=\"1\">\n",
     "  <tr>\n",
     "    <td><strong>Log files:</strong></td>\n",
     LogFun(RelSummaryLog, "Summary"),
     LogFun(RelResultLog, "Result"),
     LogFun(RelConfigLog, "Config"),
     LogFun(RelTapLog, "TAP"),
     "  </tr>\n",
     "</table>\n\n",
     lux_html_utils:html_href("h3", "", "", "#suite_config",
                              "Suite configuration"),
     html_summary_result(A, Result, Groups, IsTmp),
     html_groups2(A, Groups),
     lux_html_utils:html_anchor("h2", "", "suite_config",
                                "Suite configuration:"),
     html_div(<<"event">>, ConfigSection),
     lux_html_utils:html_footer()
    ].

html_summary_result(A, {result_summary, Summary, Sections}, Groups, IsTmp) ->
    %% io:format("Sections: ~p\n", [Sections]),
    ResultString = choose_tmp(IsTmp, "Preliminary ", "Final "),
    PrelScriptSection =
        case lux_utils:pick_opt(next_script, A#astate.opts, undefined) of
            undefined ->
                "";
            NextScript ->
                Base = filename:basename(NextScript),
                SuiteLogDir = A#astate.suite_log_dir,
                CaseLogDir = lux_case:case_log_dir(SuiteLogDir, NextScript),
                EventLog = lux_utils:join(CaseLogDir,
                                          Base ++ ?CASE_EVENT_LOG),
                ConfigLog = lux_utils:join(CaseLogDir,
                                           Base ++ ?CASE_CONFIG_LOG),
                LogFun =
                    fun(L, S) ->
                            ["    <td><strong>",
                             lux_html_utils:html_href(
                               "", drop_prefix(SuiteLogDir, L), S,
                               "text/plain"),
                             "</strong></td>\n"]
                    end,
                [
                 "\n<h2>Premature logs for current test case:",
                 "</h2>\n",
                 "<table border=\"1\">\n",
                 "  <tr>\n",
                 "    <td><strong>",
                 drop_run_dir_prefix(A, NextScript),
                 "</strong></td>\n",
                 LogFun(EventLog, "Event"),
                 LogFun(ConfigLog, "Config"),
                 "  </tr>\n",
                 "</table>\n\n<br\>\n"
                ]
        end,
    TimeHtml =
        case elapsed_time(A#astate.start_time, A#astate.end_time) of
            undefined ->
                ["<h3>Start time: ", A#astate.start_time, "</h3>\n"];
            MicrosDiff ->
                DiffStr = elapsed_time_to_str(MicrosDiff),
                ["<h3>Elapsed time: ", DiffStr, "</h3>\n"]
        end,

    [
     "\n", TimeHtml,
     "<h2>", ResultString, "result: ", Summary, "</h2>\n",
     PrelScriptSection,
     "<div class=\"case\"><pre>",
     [html_summary_section(A, S, Groups) || S <- Sections],
     "</pre></div>"
    ].

choose_tmp(IsTmp, TmpString, String) ->
    case IsTmp of
        true  -> TmpString;
        false -> String
    end.

html_summary_section(A, {section, Slogan, Count, FileBins}, Groups) ->
    [
     "<strong>", lux_html_utils:html_quote(Slogan), ": ", Count, "</strong>\n",
     case FileBins of
         [] ->
             [];
         _ ->
             [
              "<div class=\"event\"><pre>",
              [html_summary_file(A, F, Groups) || F <- FileBins],
              "</pre></div>"
             ]
     end
    ].

html_summary_file(A, {file_lineno, FileBin, LineNo}, Groups)
  when is_binary(FileBin) ->
    File = ?b2l(FileBin),
    Files =
        [HtmlLog ||
            {test_group, _Group, Cases} <- Groups,
            {test_case, Name, _Log, _Doc, HtmlLog, _Res} <- Cases,
            File =:= Name],
    PrefixedRelScript = prefixed_rel_script(A, File),
    RelFile = chop_root(drop_run_dir_prefix(A, File)),
    Label = [PrefixedRelScript, ":", LineNo],
    case Files of
        [] ->
            [lux_html_utils:html_href("#" ++ RelFile, Label), "\n"];
        [HtmlLog|_] ->
            [lux_html_utils:html_href(drop_run_log_prefix(A, HtmlLog), Label),
             "\n"]
    end.

html_groups2(A, [{test_group, _Group, Cases} | Groups]) ->
    [
     html_cases(A, Cases),
     html_groups2(A, Groups)
    ];
html_groups2(_A, []) ->
    [].

html_cases(A, [{test_case, AbsScript, _Log, Doc, HtmlLog, Res} | Cases])
  when is_list(AbsScript) ->
    Tag = "a",
    PrefixedRelScript = prefixed_rel_script(A, AbsScript),
    RelScript = drop_run_dir_prefix(A, AbsScript),
    RelHtmlLog = drop_run_log_prefix(A, HtmlLog),
    [
     lux_html_utils:html_anchor(RelScript, ""),
     "\n",
     lux_html_utils:html_href("h2", "Test case: ", "", RelHtmlLog,
                              PrefixedRelScript),
     "\n<div class=\"case\"><pre>",
     html_doc(Tag, Doc),
     %% html_href(Tag, "Raw event log: ", "", RelEventLog, RelEventLog),
     %% html_href(Tag, "Annotated script: ", "", RelHtmlLog, RelHtmlLog),
     html_result(Tag, Res, RelHtmlLog),
     "\n",
     "</pre></div>",
     html_cases(A, Cases)
    ];
html_cases(A, [{result_case, AbsScript, Reason, Details} | Cases])
  when is_list(AbsScript) ->
    Tag = "a",
    PrefixedRelScript = prefixed_rel_script(A, AbsScript),
    RelScript = chop_root(drop_run_dir_prefix(A, AbsScript)),
    [
     lux_html_utils:html_anchor(RelScript, ""),
     lux_html_utils:html_href("h2", "Test case: ", "", [RelScript, ".orig"],
                              [PrefixedRelScript]),
     "\n<div class=\"case\"><pre>",
     "\n<", Tag, ">Result: <strong>",
     lux_html_utils:html_quote(Reason),
     "</strong></",
     Tag, ">\n",
     "\n",
     Details,
     "</pre></div>",
     html_cases(A, Cases)
    ];
html_cases(_A, []) ->
    [].

html_doc(_Tag, []) ->
    [];
html_doc(Tag, [Slogan | Desc]) ->
    [
     "\n<", Tag, ">Description: <strong>",
     lux_html_utils:html_quote(Slogan),
     "</strong></",
     Tag, ">\n",
     case Desc of
         [] -> [];
         _  -> html_div(<<"event">>, lux_utils:expand_lines(Desc))
     end
    ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Annotate a lux with events from the log

annotate_event_log(#astate{log_file=EventLog} = A, WWW)
  when is_list(EventLog) ->
    try
        {Res, NewWWW} = lux_log:scan_events(EventLog, WWW),
        case Res of
            {ok, EventLog2, ConfigLog,
             Script, EventBins, ConfigBins, LogBins, ResultBins} ->
                Events = lux_log:parse_events(EventBins, []),
                %% io:format("Events: ~p\n", [Events]),
                StartTime = pick_event_time(<<"start_time">>, Events),
                EndTime = pick_event_time(<<"end_time">>, Events),
                ConfigProps = lux_log:split_config(ConfigBins),
                RunDir = pick_run_dir(ConfigProps),
                RunLogDir = pick_log_dir(ConfigProps),
                A2 = A#astate{run_dir = RunDir,
                              run_log_dir = RunLogDir,
                              start_time = StartTime,
                              end_time = EndTime},
                Timers = lux_log:extract_timers(Events),
                %% io:format("\nTimers for ~s:\n\t~p\n",
                %%           [drop_run_dir_prefix(A2, Script), Timers]),
                Csv = lux_log:timers_to_csv(Timers),
                %% io:format("\nTimers for ~s:\t~s\n",
                %%           [drop_run_dir_prefix(A2, Script),
                %%            lists:flatten(Csv)]),
                OrigScript = orig_script(A2, Script),
                A3 = A2#astate{script_file = OrigScript},
                Logs = lux_log:parse_io_logs(LogBins, []),
                Result = lux_log:parse_result(ResultBins),
                {Annotated, Files} = interleave_code(A3, Events, Script),
                Html = html_events(A3, EventLog2, ConfigLog, Script, Result,
                                   Timers, Files, Logs, Annotated, ConfigBins),
                {{ok, Csv, Html}, NewWWW};
            {error, _File, _ReasonStr} = Error ->
                {Error, NewWWW}
        end
    catch
        ?CATCH_STACKTRACE(error, Reason2, EST)
            ReasonStr =
                lists:flatten(?FF("ERROR in ~s\n~p\n\~p\n",
                                  [EventLog, Reason2, EST])),
            io:format("~s\n", [ReasonStr]),
            {{error, EventLog, ReasonStr}, WWW}
    end.

pick_event_time(Op, #event{lineno =  0,
                           shell = <<"lux">>,
                           op = Op,
                           data = [Time]}) ->
    {_Quote, Plain} = lux_log:unquote(Time),
    ?b2l(Plain);
pick_event_time(Op, Events = [_|_]) ->
    Default =
        case Op of
            <<"start_time">> -> hd(Events);
            <<"end_time">>   -> lists:last(Events);
            _                -> []
        end,
    pick_event_time(Op, Default);
pick_event_time(_Op, _Event) ->
    ?DEFAULT_TIME_STR.

interleave_code(A, Events, Script) ->
    Files = [],
    Cache = dict:new(),
    Flush = (Events =:= []),
    {SubAnnotated, Files2, _Cache2} =
        interleave_file(A, Events, Flush, Script, 1, 999999, [], Files, Cache),
    {SubAnnotated, Files2}.

interleave_file(A, Events, Flush, Script,
                FirstLineNo, MaxLineNo,
                CmdStack, Files, Cache)
  when is_list(Script) ->
    OrigScript = A#astate.script_file,
    {FCH, Files2} =
        lookup_file(Script, OrigScript, FirstLineNo, MaxLineNo,
                    CmdStack, Files, Cache),
    case FCH of
        #code_html{} = CH ->
            {[CH], Files2, Cache};
        #file{} = F ->
            AllLines = F#file.all_lines,
            CodeLines =
                try
                    lists:nthtail(FirstLineNo-1, AllLines)
                catch
                    _Class:_Reason ->
                        AllLines
                end,
            Acc = [],
            interleave_loop(A, Events, Flush, CodeLines,
                            FirstLineNo, MaxLineNo,
                            Acc, CmdStack,
                            F, Files2, Cache)
    end.

lookup_file(Script, OrigScript, FirstLineNo, MaxLineNo,
            CmdStack, Files, Cache) ->
    case dict:find({OrigScript, FirstLineNo, MaxLineNo}, Cache) of
        {ok, #code_html{} = CH} ->
            {CH#code_html{cmd_stack = CmdStack}, Files};
        error ->
            case lists:keyfind(OrigScript, #file.orig_script, Files) of
                #file{} = F ->
                    {F, Files};
                false ->
                    AllLines =
                        case file:read_file(OrigScript) of
                            {ok, ScriptBin} ->
                                binary:split(ScriptBin, <<"\n">>, [global]);
                            {error, FileReason} ->
                                ReasonStr = OrigScript ++ ": " ++
                                    file:format_error(FileReason),
                                io:format("ERROR(lux): ~s\n", [ReasonStr]),
                                []
                        end,
                    ScriptComps = lux_utils:filename_split(Script),
                    F = #file{script = Script,
                              script_comps = ScriptComps,
                              orig_script = OrigScript,
                              all_lines = AllLines},
                    {F, [F | Files]}
            end
    end.

interleave_loop(A, [#event{lineno =  LineNo,
                           shell = Shell,
                           op = Op,
                           quote = Quote,
                           data = RevData} | Events],
                Flush, CodeLines,
                CodeLineNo, MaxLineNo,
                Acc, CmdStack,
                F, Files, Cache) ->
    TmpFlush = false,
    {CodeLines2, CodeLineNo2, CH, Cache2} =
        pick_code(F, CodeLines,
                  CodeLineNo, LineNo,
                  TmpFlush, CmdStack,
                  Cache),
    ScriptComps = F#file.script_comps,
    Data = ?l2b(lists:reverse(RevData)),
    DataLines =
        case Data of
            <<>> ->
                [<<>>];
            Unsplit when Quote =:= quote ->
                lux_log:split_quoted_lines(Unsplit);
            Split ->
                [Split]
        end,
    EH = #event_html{script_comps = ScriptComps,
                     lineno = LineNo,
                     cmd_stack = CmdStack,
                     op = Op,
                     shell = Shell,
                     data = DataLines},
    Acc2 =
        case CH#code_html.lines of
            [] -> [EH | Acc];
            _  -> [EH, CH | Acc]
        end,
    interleave_loop(A, Events,
                    Flush, CodeLines2,
                    CodeLineNo2, MaxLineNo,
                    Acc2, CmdStack,
                    F, Files, Cache2);
interleave_loop(A, [#body{} = B | Events],
                Flush, CodeLines,
                CodeLineNo, MaxLineNo,
                Acc, CmdStack,
                F, Files, Cache) ->
    ScriptComps = F#file.script_comps,
    CmdPos = #cmd_pos{rev_file = ScriptComps,
                      lineno = B#body.invoke_lineno,
                      type = undefined},
    CmdStack2 = [CmdPos | CmdStack],
    SubScript = B#body.file,
    OrigSubScript = orig_script(A, SubScript),
    SubA = A#astate{script_file = OrigSubScript},
    {SubAnnotated, Files2, Cache2} =
        interleave_file(SubA, B#body.events, Flush, SubScript,
                        B#body.first_lineno, B#body.last_lineno,
                        CmdStack2, Files, Cache),
    Event = #body_html{script = SubScript,
                       orig_script = OrigSubScript,
                       cmd_stack = CmdStack2,
                       lineno = B#body.first_lineno,
                       lines = SubAnnotated},
    interleave_loop(A, Events,
                    Flush, CodeLines,
                    CodeLineNo, MaxLineNo,
                    [Event | Acc], CmdStack,
                    F, Files2, Cache2);
interleave_loop(_A, [],
                Flush, CodeLines,
                CodeLineNo, MaxLineNo,
                Acc, CmdStack,
                F, Files, Cache) ->
    {_Skipped, _CodeLineNo, CH, Cache2} =
        pick_code(F, CodeLines,
                  CodeLineNo, MaxLineNo,
                  Flush, CmdStack, Cache),
    {lists:reverse([CH | Acc]), Files, Cache2}.

pick_code(F, Lines, CodeLineNo, MaxLineNo, Flush, CmdStack, Cache) ->
    {Lines2, CodeLineNo2, Code} =
        do_pick_code(F, Lines, CodeLineNo, MaxLineNo, Flush, []),
    ScriptComps = F#file.script_comps,
    CH = #code_html{script_comps = ScriptComps,
                    lineno = CodeLineNo,
                    cmd_stack = CmdStack,
                    lines = Code},
    Cache2 = dict:store({F#file.orig_script, CodeLineNo, MaxLineNo}, CH, Cache),
    {Lines2, CodeLineNo2, CH, Cache2}.

do_pick_code(F, [Line | Lines], CodeLineNo, LineNo, Flush, Acc)
  when Flush orelse LineNo >= CodeLineNo ->
    do_pick_code(F, Lines, CodeLineNo+1, LineNo, Flush, [Line | Acc]);
do_pick_code(_F, Lines, CodeLineNo, _LineNo, _Flush, Acc) ->
    {Lines, CodeLineNo, lists:reverse(Acc)}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Return event log as HTML

html_events(A, EventLog, ConfigLog, Script, Result,
            Timers, Files, Logs, Annotated, ConfigBins)
  when is_list(EventLog), is_list(ConfigLog), is_list(Script) ->
    EventLogDir = A#astate.new_log_dir,
    EventLogBase = lux_utils:join(EventLogDir, filename:basename(Script)),
    ExtraLogs = EventLogBase ++ ?CASE_EXTRA_LOGS,
    Dir = filename:basename(EventLogDir),
    LogFun =
        fun(L, S, Type) ->
                ["    <td><strong>",
                 lux_html_utils:html_href(
                   "", drop_prefix(EventLogDir, L), S, Type),
                 "</strong></td>\n"]
        end,
    PrefixScript = A#astate.case_prefix ++ drop_run_dir_prefix(A, Script),
    TimeHtml =
        case elapsed_time(A#astate.start_time, A#astate.end_time) of
            undefined ->
                ["<h3>Start time: ", A#astate.start_time, "</h3>\n"];
            MicrosDiff ->
                DiffStr = elapsed_time_to_str(MicrosDiff),
                ["<h3>Elapsed time: ", DiffStr, "</h3>\n"]
        end,
    RelEventLogDir = filename:split(drop_run_log_prefix(A, EventLogDir)),
    RelSummaryLog = dotdot(RelEventLogDir, ?SUITE_SUMMARY_LOG ++ ".html"),
    [
     lux_html_utils:html_header(["Lux event log (", Dir, ")"]),
     "\n", lux_html_utils:html_href("h2", "", "", "#annotate", PrefixScript),
     html_result("h2", Result, ""),
     lux_html_utils:html_anchor("info", ""),
     "\n", TimeHtml,
     lux_html_utils:html_href("h3", "", "", "#config", "Script configuration"),
     lux_html_utils:html_href("h3", "", "", "#stats", "Script statistics"),
     lux_html_utils:html_href("h3", "", "", "#cleanup", "Cleanup"),
     "\n<h3>Source files: ",
     html_scripts(A, Files, main),
     "\n</h3>",
     "\n<h3>", lux_html_utils:html_anchor("logs", "Log files"), ":</h3>\n ",
     "<table border=\"1\">\n",
     "  <tr>\n",
     LogFun(EventLog, "Event", "text/plain"),
     LogFun(ConfigLog, "Config", "text/plain"),
     case filelib:is_dir(ExtraLogs) of
         true  -> LogFun(ExtraLogs, "Extra", "");
         false -> "    <td><strong>No extra</strong></td>\n"
     end,
     html_logs(A, Logs),
     "  </tr>\n",
     "</table>\n",
     lux_html_utils:html_href("h3", "", "", RelSummaryLog,
                              "Back to summary log"),

     "\n", lux_html_utils:html_anchor("h2", "", "annotate",
                                      "Annotated source code"),"\n",
     html_code(A, Annotated, undefined),

     "<div class=\"code\"><pre><a name=\"cleanup\"></a></pre></div>\n",

     lux_html_utils:html_anchor("h2", "", "stats", "Script statistics:"),
     LogFun(EventLog ++ ".csv", "Csv data file", "application/excel"),
     lux_html_utils:html_href("h4", "", "", "#shell_stats", "Shells"),
     lux_html_utils:html_href("h4", "", "", "#macro_exact_stats",
                              "Macros"),
     lux_html_utils:html_href("h4", "", "", "#macro_accum_stats",
                              "Accumulated per macro"),
     html_stats(Timers),
     lux_html_utils:html_anchor("h2", "", "config", "Script configuration:"),
     html_config(ConfigBins),
     lux_html_utils:html_footer()
    ].

dotdot(["."], Base) ->
    Base;
dotdot(Path, Base) ->
    DotDots = filename:join([".." || _ <- Path]),
    filename:join([DotDots, Base]).

html_stats(Timers) ->
    {ShellSplit, ExactMacroSplit, AccumMacroSplit} =
        lux_html_utils:split_timers(Timers),
    [
     lux_html_utils:html_anchor("h3", "", "shell_stats",
                                "Statistics per shell"),
     html_timers("Shell", ShellSplit),
     lux_html_utils:html_anchor("h3", "", "macro_exact_stats",
                                "Statistics per macro"),
     html_timers("Macro", ExactMacroSplit),
     lux_html_utils:html_anchor("h3", "", "macro_accum_stats",
                                "Statistics accumulated per macro"),
     html_timers("Macro", AccumMacroSplit)
    ].

html_timers(Label, {Total, SplitSums}) ->
    [
     "<table border=\"1\">\n",
     html_timer_row(["<strong>", Label, "</strong>"], Total, [], Total),
     [html_timer_row(Tag, Sum, List, Total) ||
         {Tag, Sum, List} <- SplitSums],
     "</table>\n\n"
    ].

html_timer_row(Label, Sum, List, Total) ->
    [
     "  <tr>\n",
     "    <td>",
     case Label of
         ""   -> "N/A";
         <<>> -> "N/A";
         _    -> Label
     end,
     "</td>\n",
     if
         Sum =:= undefined ->
             [
              "    <td></td>\n",
              "    <td></td>\n"
             ];
         is_integer(Sum) ->
             Perc =
                 case Total of
                     0 -> 0;
                     _ -> (Sum*100) div Total
                 end,
             [
              "    <td align=\"right\">", ?i2l(Sum), "</td>\n",
              "    <td align=\"right\">", ?i2l(Perc), "%</td>\n"
             ]
     end,
     case List of
         [] ->
             [
              "    <td>Timer</td>\n"
              "    <td>", "Max", "</td>\n",
              "    <td>", "Match", "</td>\n",
              "    <td>", "Send", "</td>\n",
              "    <td>", "Call stack", "</td>\n"
             ];
         _ ->
             [
              "    <td></td>\n",
              "    <td></td>\n",
              "    <td></td>\n",
              "    <td></td>\n",
              "    <td></td>\n"
             ]
     end,
     "  </tr>\n",
     [["  <tr>\n",
       "    <td></td>\n",
       "    <td></td>\n",
       "    <td></td>\n",
       begin
           Max = T#timer.max_time,
           Elapsed = T#timer.elapsed_time,
           ElapsedTd =
               if
                   Elapsed =:= undefined ->
                       html_td("N/A", warning, "right", "");
                   true ->
                       html_td(?i2l(Elapsed), no_data, "right", "")
               end,
           [
            ElapsedTd,
            if
                Max =:= 0 ->
                    html_td("N/A", warning, "right", "");
                Max =:= infinity ->
                    html_td("N/A", warning, "right", "");
                Elapsed =:= undefined ->
                    html_td("N/A", no_data, "right", "");
                T#timer.status =/= matched ->
                    html_td([?i2l((Elapsed*100) div Max), "%"],
                            fail, "right", "");
                Elapsed > trunc(Max * ?TIMER_THRESHOLD) ->
                    html_td([?i2l((Elapsed*100) div Max), "%"],
                            warning, "right", "");
                true ->
                    html_td([?i2l((Elapsed*100) div Max), "%"],
                            no_data, "right", "")
            end
           ]
       end,
       "    <td>", html_timer_data(T#timer.match_lineno,
                                   T#timer.match_data), "</td>\n",
       "    <td>", html_timer_data(T#timer.send_lineno,
                                   T#timer.send_data), "</td>\n",
       "    <td>", T#timer.callstack, "</td>\n",
       "  </tr>\n"] || T <- List
     ]
    ].

html_timer_data(L, Data) ->
    Pretty = lux_utils:pretty_full_lineno(L),
    ToolTip = lux_utils:expand_lines(Data),
    [
     "\n<a href=\"#", lux_html_utils:html_quote(Pretty),
     "\" title=\"", lux_html_utils:html_quote(ToolTip),
     "\">", Pretty, "</a>"
    ].

html_result(Tag, {warnings_and_result, Warnings, Result}, HtmlLog) ->
    PrettyWarnings =
        [["\n<", Tag,
          "><strong>Warning at line ", W, "</strong></",
          Tag, ">\n"] ||
            W <- Warnings],
    [
     PrettyWarnings,
     html_result2(Tag, Result, HtmlLog)
    ].

html_result2(Tag, Result, HtmlLog) ->
    case Result of
        success ->
            ["\n<", Tag, ">Result: <strong>SUCCESS</strong></", Tag, ">\n"];
        warning ->
            ["\n<", Tag, ">Result: <strong>WARNING</strong></", Tag, ">\n"];
        skip ->
            ["\n<", Tag, ">Result: <strong>SKIP</strong></", Tag, ">\n"];
        {skip, _} ->
            ["\n<", Tag, ">Result: <strong>SKIP</strong></", Tag, ">\n"];
        {error_line, RawLineNo, Reason} ->
            Anchor = RawLineNo,
            [
             "\n<", Tag, ">Result: <strong>ERROR at line ",
             lux_html_utils:html_href([HtmlLog, "#", Anchor], Anchor),
             "<h3>Reason</h3>",
             html_div(<<"event">>, lux_utils:expand_lines(Reason))
            ];
        {error, Reason} ->
            [
             "\n<", Tag, ">Result: <strong>ERROR</strong></", Tag, ">\n",
             "<h3>Reason</h3>",
             html_div(<<"event">>, lux_utils:expand_lines(Reason))
            ];
        {How, RawLineNo, ShellName, ExpectedTag, Expected, Actual, Details}
          when How =:= fail orelse How =:= warning ->
            HtmlDiff = html_diff(ExpectedTag, Expected, Details),
            Anchor = RawLineNo,
            [
             "\n<", Tag, ">",
             lux_html_utils:html_href([HtmlLog, "#info"], "Result"),
             ": <strong>",
             lux_html_utils:html_href([HtmlLog, "#failed"], "FAIL"),
             " at line ",
             lux_html_utils:html_href([HtmlLog, "#", Anchor], Anchor),
             "</strong> in shell ",
             lux_html_utils:html_href([HtmlLog, "#logs"], ShellName),
             "</", Tag, ">\n",

             "<h3>Expected:</h3>",
             html_div(<<"event">>, lux_utils:expand_lines(Expected)),

             "<h3>Actual: ", lux_html_utils:html_quote(Actual), "</h3>",
             "<div class=\"event\"><pre>",
             lux_html_utils:html_quote(lux_utils:expand_lines(Details)),
             "</pre></div>",

             lux_html_utils:html_anchor("failed", ""),
             "\n<h3>Diff:</h3>",
             "<div class=\"event\"><pre>",
             HtmlDiff,
             "</pre></div>"
            ]
    end.

html_diff(ExpectedTag, Expected, Details) ->
%%  Mode = flat, % 'deep' gives insanely bad performance for big diffs
    Mode = deep,
    lux_utils:diff_iter(ExpectedTag, Expected, Details, Mode, fun emit/4).

emit(Op, Mode, Context, Acc) when Mode =:= flat;
                                  Mode =:= deep ->
    case Op of
        {common, Common} ->
            [Acc,
             "\n", html_color(common, Mode, <<"  ">>,
                              lux_utils:shrink_lines(Common))];
        {del, Del} ->
            [Acc,
             "\n", html_color(del, Mode, <<"- ">>, Del)];
        {add, Add} ->
            Prefix =
                case Context of
                    first  -> <<"  ">>;
                    middle -> <<"+ ">>;
                    last   -> <<"  ">>
                end,
            [Acc,
             "\n", html_color(add, Mode, Prefix, Add)];
        {replace, Del, Add} when Mode =:= flat ->
            [
             Acc,
             "\n", html_color(del, Mode, <<"- ">>, Del),
             "\n", html_color(add, Mode, <<"+ ">>, Add)
            ];
        {nested, Del, Add, [_SingleNestedOp]} when Mode =:= deep ->
            %% Skip underline
            [
             Acc,
             "\n", html_color(del, Mode, <<"- ">>, Del),
             "\n", html_color(add, Mode, <<"+ ">>, Add)
            ];
        {nested, _OrigDel, _OrigAdd, RevNestedAcc} when Mode =:= deep ->
            NestedAcc = lists:reverse(RevNestedAcc),
            Del = ?l2b(nested_emit(del, NestedAcc, [])),
            Add = ?l2b(nested_emit(add, NestedAcc, [])),
            Del2 = binary:split(Del, <<"\n">>, [global]),
            Add2 = binary:split(Add, <<"\n">>, [global]),
            [
             Acc,
             "\n", html_color(del, nested, <<"- ">>, Del2),
             "\n", html_color(add, nested, <<"+ ">>, Add2)
            ]
    end;
emit(Op, Mode, _Context, Acc) when Mode =:= nested ->
    [Op | Acc].

nested_emit(Op, [NestedOp | Rest], Acc) ->
    case NestedOp of
        {common, Common} ->
            NewAcc = [Acc, lux_html_utils:html_quote(Common)],
            nested_emit(Op, Rest, NewAcc);
        {del, Del} when Op =:= del ->
            NewAcc = [Acc, tag(<<"mark">>, lux_html_utils:html_quote(Del))],
            nested_emit(Op, Rest, NewAcc);
        {add, Add} when Op =:= add ->
            NewAcc = [Acc, tag(<<"mark">>, lux_html_utils:html_quote(Add))],
            nested_emit(Op, Rest, NewAcc);
        {replace, Del, Add} ->
            nested_emit(Op, [{del, Del}, {add, Add} | Rest], Acc);
        _Ignore ->
            nested_emit(Op, Rest, Acc)
    end;
nested_emit(_Op, [], Acc) ->
    Acc.

html_color(Op, Mode, Prefix, Text) ->
    Color =
        case Op of
            common -> <<"black">>;
            del    -> <<"red">>;
            add    -> <<"blue">>
        end,
    Bold = <<"b">>,
    QuotedPrefix = lux_html_utils:html_quote(Prefix),
    [
     <<"<font color=\"">>, Color, <<"\">">>,
     tag(Bold, html_expand_lines(Text, QuotedPrefix, Mode)),
     <<"</font>">>
    ].

html_expand_lines([], _QuotedPrefix, _Quote) ->
    [];
html_expand_lines([H|T], QuotedPrefix, nested) ->
    [[QuotedPrefix, H] | [[<<"\n">>, QuotedPrefix, L] || L <- T]];
html_expand_lines([H|T], QuotedPrefix, _Quotequote) ->
    [[QuotedPrefix, lux_html_utils:html_quote(H)] |
     [[<<"\n">>, QuotedPrefix, lux_html_utils:html_quote(L)] || L <- T]].

tag(Tag, Text) ->
    [<<"<">>, Tag, <<">">>, Text, <<"</">>, Tag, <<">">>].

html_config(Config) when is_list(Config) ->
    html_div(<<"event">>, lux_utils:expand_lines(Config));
html_config(Config) when is_binary(Config) ->
    html_div(<<"event">>, Config).

html_logs(A, [{log, ShellName, Stdin, Stdout} | Logs]) ->
    [
     "\n<tr>\n    ",
     "<td><strong>Shell ", ShellName, "</strong></td>",
     "<td><strong>",
     lux_html_utils:html_href("", rel_log(A, Stdin), "Stdin", "text/plain"),
     "</strong></td>",
     "<td><strong>",
     lux_html_utils:html_href("", rel_log(A, Stdout), "Stdout", "text/plain"),
     "</strong></td>",
     "\n</tr>\n",
     html_logs(A, Logs)
    ];
html_logs(_A, []) ->
    [].

html_code(A, Annotated, Prev) ->
    html_code2(A, Annotated, Prev, Prev).

html_code2(A, [Ann | Annotated], Prev, Orig) ->
    case Ann of
        #code_html{script_comps = ScriptComps,
                   lineno = CodeLineNo,
                   cmd_stack = CmdStack,
                   lines = Code} ->
            Curr = code,
            Fun = fun(L, C) ->
                          CmdPos = #cmd_pos{rev_file = ScriptComps,
                                            lineno = C,
                                            type = undefined},
                          CmdStack2 = [CmdPos | CmdStack],
                          FullLineNo = lux_utils:pretty_full_lineno(CmdStack2),
                          {[
                            case L of
                                <<"[cleanup]">> -> "<a name=\"cleanup\"></a>\n";
                                _               -> ""
                            end,
                            lux_html_utils:html_anchor(FullLineNo, FullLineNo),
                            ": ",
                            lux_html_utils:html_quote(L),
                            "\n"
                           ],
                           C+1}
                  end,
            [
             html_change_div_mode(Curr, Prev),
             element(1, lists:mapfoldl(Fun, CodeLineNo, Code)),
             "\n",
             html_code2(A, Annotated, Curr, Orig)
            ];
        #event_html{script_comps = ScriptComps,
                    lineno = LineNo,
                    cmd_stack = CmdStack,
                    op = Op,
                    shell = Shell,
                    data = Data} ->
            Curr = event,
            Data =
                case Op of
                    <<"expect">> ->
                        lists:append([binary:split(D, <<"\\\\R">>, [global]) ||
                                         D <- Data]);
                    _ ->
                        Data
                end,
            CmdPos = #cmd_pos{rev_file = ScriptComps,
                              lineno = LineNo,
                              type = undefined},
            CmdStack2 = [CmdPos | CmdStack],
            FullLineNo = lux_utils:pretty_full_lineno(CmdStack2),
            Html = ["\n", Shell, "(", FullLineNo, "): ", Op, " "],
            [
             html_change_div_mode(Curr, Prev),
             lux_html_utils:html_quote(Html),
             html_opt_div(Op, Data),
             html_code2(A, Annotated, Curr, Orig)
            ];
        #body_html{script = SubScript,
                   orig_script = OrigSubScript,
                   cmd_stack = CmdStack,
                   lineno = _LineNo,
                   lines = SubAnnotated} ->
            FullLineNo = lux_utils:pretty_full_lineno(CmdStack),
            RelSubScript = drop_run_dir_prefix(A, SubScript),
            if
                OrigSubScript =/= A#astate.script_file ->
                    [
                     html_change_div_mode(event, Prev),
                     html_opt_div(<<"file">>,
                                  [["\nentering file: ", RelSubScript]]),
                     html_code(A, SubAnnotated, event),
                     html_change_div_mode(code, event),
                     lux_html_utils:html_anchor(FullLineNo, FullLineNo), ": ",
                     html_change_div_mode(event, code),
                     html_opt_div(<<"file">>,
                                  [["exiting file: ", RelSubScript]]),
                     html_code2(A, Annotated, event, Orig)
                    ];
                true ->
                    [
                     html_code(A, SubAnnotated, Prev),
                     %% html_anchor(FullLineNo, FullLineNo), ": \n",
                     html_code2(A, Annotated, Prev, Orig)
                    ]
            end
    end;
html_code2(_A, [], Prev, Orig) ->
    html_change_div_mode(Orig, Prev).

html_change_div_mode(To, From) ->
    case {To, From} of
        {undefined, undefined} -> "";
        {undefined, code}      -> "</pre></div>\n";
        {undefined, event}     -> "</pre></div>\n";
        {code, undefined}      -> "\n<div class=\"code\"><pre>\n";
        {code, code}           -> "";
        {code, event}          -> "</pre></div>\n<div class=\"code\"><pre>";
        {event, undefined}     -> "\n<div class=\"event\"><pre>\n";
        {event, event}         -> "";
        {event, code}          -> "</pre></div>\n<div class=\"event\"><pre>\n"
    end.

html_opt_div(Op, Data) ->
    Html = lux_utils:expand_lines(Data),
    case Op of
        <<"send">>   -> html_div(Op, Html);
        <<"recv">>   -> html_div(Op, Html);
        <<"expect">> -> html_div(Op, Html);
        <<"skip">>   -> html_div(Op, Html);
        <<"match">>  -> html_div(Op, Html);
        _            -> lux_html_utils:html_quote(Html)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Helpers

html_div(Class, Html) ->
    [
     "\n<div class=\"", Class, "\"><pre>",
     lux_html_utils:html_quote(Html),
     "</pre></div>\n"
    ].

html_scripts(A, [#file{script = Path, orig_script = OrigScript} | Files],
             Level) ->
    RelScript = rel_orig_script(A, OrigScript, Level),
    RelPath0 = drop_run_dir_prefix(A, Path),
    RelPath = add_up_dir(A, RelPath0, Level),
    [
     "\n<br/>", lux_html_utils:html_href("", RelScript, RelPath, "text/plain"),
     html_scripts(A, Files, include)
    ];
html_scripts(_A, [], _Level) ->
    ["<br/>"].

prefixed_rel_script(A, AbsScript) when is_list(AbsScript) ->
    RelScript = drop_rel_dir_prefix(A, rel_script(A, AbsScript)),
    A#astate.case_prefix ++ RelScript.

drop_rel_dir_prefix(A, RelPath) when is_list(RelPath) ->
    RelDir = drop_prefix(A#astate.suite_log_dir, A#astate.new_log_dir),
    drop_prefix(RelDir, RelPath).

add_up_dir(_A, RelPath, main) when is_list(RelPath)->
    RelPath;
add_up_dir(_A, AbsPath, include) when hd(AbsPath) =:= $/ ->
    AbsPath;
add_up_dir(A, RelPath, include) when is_list(RelPath) ->
    case drop_prefix(A#astate.suite_log_dir, A#astate.new_log_dir) of
        "." ->
            RelPath;
        RelDir ->
            UpDir = filename:join([".." || _ <- filename:split(RelDir)]),
            filename:join([UpDir, RelPath])
    end.

drop_run_dir_prefix(#astate{run_dir=LogDir}, File)
  when is_list(LogDir), is_list(File) ->
    drop_prefix(LogDir, File).

drop_run_log_prefix(#astate{run_log_dir=LogDir}, File)
  when is_list(LogDir), is_list(File) ->
    drop_prefix(LogDir, File).

drop_new_log_prefix(#astate{new_log_dir=LogDir}, File)
  when is_list(LogDir), is_list(File) ->
    drop_prefix(LogDir, File).

drop_prefix(Dir, File) when is_list(Dir), is_list(File) ->
    lux_utils:drop_prefix(Dir, File).

pick_run_dir(ConfigProps) ->
    pick_dir_prop(<<"run_dir">>, ConfigProps).

pick_log_dir(ConfigProps) ->
    pick_dir_prop(<<"log_dir">>, ConfigProps).

pick_time_prop(Tag, ConfigProps) ->
    ?b2l(lux_log:find_config(Tag, ConfigProps, ?DEFAULT_TIME)).

pick_dir_prop(Tag, ConfigProps) ->
    case lux_log:find_config(Tag, ConfigProps, undefined) of
        undefined ->
            {ok, Cwd} = file:get_cwd(),
            Cwd;
        Bin ->
            ?b2l(Bin)
    end.

orig_script(A, AbsScript) when is_list(AbsScript) ->
    case rel_script(A, AbsScript) of
        ".." ++ _ ->  RelScript0 = AbsScript;
        RelScript0 -> ok
    end,
    RelScript =
        case filename:pathtype(RelScript0) of
            absolute -> tl(RelScript0);
            _Type    -> RelScript0
        end,
    lux_utils:join(A#astate.suite_log_dir, RelScript ++ ".orig").

rel_script(A, Script) when is_list(Script) ->
    chop_root(drop_run_dir_prefix(A, Script)).

rel_log(A, AbsLog) when is_list(AbsLog) ->
    RelLog = chop_root(drop_run_log_prefix(A, AbsLog)),
    drop_rel_dir_prefix(A, RelLog).

chop_root(AbsPath) ->
    case AbsPath of
        "/" ++ RelPath -> ok;
        RelPath        -> ok
    end,
    RelPath.

rel_orig_script(A, AbsScript, Level) when is_list(AbsScript) ->
    OptRelScript = drop_prefix(A#astate.suite_log_dir, AbsScript),
    RelScript = chop_root(OptRelScript),
    if
        RelScript =/= OptRelScript -> RelScript;
        Level =:= main             -> drop_rel_dir_prefix(A, RelScript);
        Level =:= include          -> add_up_dir(A, RelScript, Level)
    end.

elapsed_time(StartStr, EndStr) ->
    Start = parse_time(StartStr),
    End = parse_time(EndStr),
    if
        Start =:= undefined ->
            undefined;
        End =:= undefined ->
            undefined;
        true ->
            {StartDateTime, StartMicros} = Start,
            {EndDateTime, EndMicros} = End,
            MicrosDiff = EndMicros - StartMicros,
            if
                StartDateTime =:= EndDateTime ->
                    MicrosDiff;
                true ->
                    {Days, Time} = calendar:time_difference(StartDateTime,
                                                            EndDateTime),
                    {Hours, Mins, Secs} = Time,
                    Hours2 = Hours + (Days * 24),
                    Secs2 = calendar:time_to_seconds({Hours2, Mins, Secs}),
                    (Secs2 * ?ONE_SEC_MICROS) + MicrosDiff
            end
    end.

%% Format: 2016-11-25 10:51:18.307279
parse_time(?DEFAULT_TIME_STR) ->
    undefined;
parse_time(DateTime) ->
    [Date, Time] = string:tokens(DateTime, " "),
    [Year, Mon, Day] = string:tokens(Date, "-"),
    [Time2, Millis] = string:tokens(Time, "."),
    [Hour, Min, Sec] = string:tokens(Time2, ":"),
    {{{list_to_integer(Year), list_to_integer(Mon), list_to_integer(Day)},
      {list_to_integer(Hour), list_to_integer(Min), list_to_integer(Sec)}},
     list_to_integer(Millis)}.

elapsed_time_to_str(MicrosDiff) ->
    TotalSecs = (MicrosDiff div ?ONE_SEC_MICROS),
    Micros = MicrosDiff - (TotalSecs * ?ONE_SEC_MICROS),
    {Hours, Mins, Secs} = calendar:seconds_to_time(TotalSecs),
    lists:concat([Hours, ":", Mins, ":", Secs, ".",
                  string:right(?i2l(Micros), 6, $0), " (h:m:s.us)"]).
