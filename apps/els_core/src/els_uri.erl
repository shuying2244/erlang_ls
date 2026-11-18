%%==============================================================================
%% Library to parse RFC-3986 URIs
%%==============================================================================
%% For details, see: http://tools.ietf.org/html/rfc3986
%%==============================================================================
-module(els_uri).

%%==============================================================================
%% Exports
%%==============================================================================
-export([
    module/1,
    path/1,
    uri/1,
    app/1
]).

%%==============================================================================
%% Types
%%==============================================================================
-type path() :: binary().

-export_type([path/0]).

%%==============================================================================
%% Includes
%%==============================================================================
-include("els_core.hrl").

-spec app(uri() | [binary()]) -> {ok, atom()} | error.
app(Uri) when is_binary(Uri) ->
    app(lists:reverse(filename:split(path(Uri))));
app([]) ->
    error;
app([_File, <<"src">>, AppBin0 | _]) ->
    case binary:split(AppBin0, <<"-">>) of
        [AppBin, _Vsn] ->
            {ok, binary_to_atom(AppBin)};
        [AppBin] ->
            {ok, binary_to_atom(AppBin)}
    end;
app([_ | Rest]) ->
    app(Rest).

-spec module(uri()) -> atom().
module(Uri) ->
    binary_to_atom(filename:basename(path(Uri), <<".erl">>), utf8).

-spec path(uri()) -> path().
path(Uri) ->
    path(Uri, els_utils:is_windows()).

-spec path(uri(), boolean()) -> path().
path(Uri, IsWindows) ->
    #{
        host := Host,
        path := Path0,
        scheme := <<"file">>
    } = uri_string:normalize(Uri, [return_map]),
    Path = uri_string:percent_decode(Path0),
    case {IsWindows, Host} of
        {true, <<>>} ->
            % Windows drive letter, have to strip the initial slash
            Path1 = re:replace(
                Path, "^/([a-zA-Z]:)(.*)", "\\1\\2", [{return, binary}]
            ),
            lowercase_drive_letter(Path1);
        {true, _} ->
            <<"//", Host/binary, Path/binary>>;
        {false, <<>>} ->
            Path;
        {false, _} ->
            error(badarg)
    end.

-spec uri(path()) -> uri().
uri(Path) ->
    %% file:path_open/3 返回字符串。先转成二进制再切分，盘符的百分号编码才一致。
    [Head | Tail] = filename:split(els_utils:to_binary(Path)),
    {Host, Path1} =
        case {els_utils:is_windows(), Head} of
            {false, <<"/">>} ->
                {<<>>, uri_join(Tail)};
            {true, X} when X =:= <<"//">> orelse X =:= <<"\\\\">> ->
                [H | T] = Tail,
                {H, uri_join(T)};
            {true, <<DriveLetter, $:, _/binary>>} when
                (DriveLetter >= $A andalso DriveLetter =< $Z) orelse
                    (DriveLetter >= $a andalso DriveLetter =< $z)
            ->
                % 只编码真正的盘符前缀，例如 "c:/" -> "c%3A"。
                H1 = <<DriveLetter, "%3A">>,
                {<<>>, uri_join([H1 | Tail])};
            {true, _} ->
                % 不是盘符，沿用原来的前两个字符，避免把 Unix 路径写成盘符。
                H1 = string:slice(Head, 0, 2),
                {<<>>, uri_join([H1 | Tail])}
        end,

    els_utils:to_binary(
        uri_string:recompose(#{
            scheme => <<"file">>,
            host => Host,
            path => [$/, Path1]
        })
    ).

-spec uri_join([path()]) -> iolist().
uri_join(List) ->
    lists:join(<<"/">>, List).

-spec lowercase_drive_letter(binary()) -> binary().
lowercase_drive_letter(<<Drive0, ":", Rest/binary>>) ->
    Drive = string:to_lower(Drive0),
    <<Drive, ":", Rest/binary>>;
lowercase_drive_letter(Path) ->
    Path.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

path_uri_test_() ->
    [
        ?_assertEqual(
            <<"/foo/bar.erl">>,
            path(<<"file:///foo/bar.erl">>)
        ),
        ?_assertEqual(
            <<"/foo/bar baz.erl">>,
            path(<<"file:///foo/bar%20baz.erl">>)
        ),
        ?_assertEqual(
            <<"/foo/bar.erl">>,
            path(uri(path(<<"file:///foo/bar.erl">>)))
        ),
        ?_assertEqual(
            <<"/foo/bar baz.erl">>,
            path(uri(<<"/foo/bar baz.erl">>))
        ),
        ?_assertEqual(
            <<"file:///foo/bar%20baz.erl">>,
            uri(<<"/foo/bar baz.erl">>)
        )
    ].

path_windows_test() ->
    ?assertEqual(
        <<"c:/foo/bar.erl">>,
        path(<<"file:///C%3A/foo/bar.erl">>, true)
    ).
-endif.
