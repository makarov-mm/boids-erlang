%%% flock.erl — coordinator. Gathers a snapshot of every boid process,
%%% broadcasts it, renders an ASCII frame. Also: chaos/0 kills a random
%%% boid to demonstrate supervisor-driven fault tolerance.
-module(flock).

-export([run/0, run/2, demo/0, chaos/0]).

-define(W, 80).
-define(H, 24).

%% Interactive: flock:run(). / flock:run(NBoids, NFrames).
run() -> run(60, 300).

run(N, Frames) ->
    {ok, _Sup} = boid_sup:start_link(),
    [begin {ok, _} = boid_sup:spawn_boid(I) end || I <- lists:seq(1, N)],
    io:format("~p boids spawned, ~p BEAM processes alive~n",
              [N, erlang:system_info(process_count)]),
    loop(Frames, true).

%% Non-interactive demo used for verification: renders a few frames,
%% kills a boid mid-flight, prints proof of restart.
demo() ->
    {ok, _Sup} = boid_sup:start_link(),
    N = 60,
    [begin {ok, _} = boid_sup:spawn_boid(I) end || I <- lists:seq(1, N)],
    io:format("spawned ~p boids~n", [N]),
    loop(30, false),                       % warm up, no draw
    draw(snapshot()),
    Before = length(boids()),
    chaos(),                               % murder a random boid
    timer:sleep(50),                       % supervisor restarts it
    After = length(boids()),
    io:format("boids before kill: ~p, after supervisor restart: ~p~n",
              [Before, After]),
    loop(30, false),
    draw(snapshot()),
    init:stop().

chaos() ->
    Bs = boids(),
    Victim = lists:nth(rand:uniform(length(Bs)), Bs),
    io:format("killing boid ~p...~n", [Victim]),
    exit(Victim, kill).

%%--------------------------------------------------------------------
loop(0, _) -> ok;
loop(K, Draw) ->
    Snapshot = snapshot(),
    [gen_server:cast(Pid, {tick, Snapshot}) || {Pid, _, _, _, _} <- Snapshot],
    case Draw of
        true  -> draw(Snapshot), timer:sleep(60);
        false -> timer:sleep(5)
    end,
    loop(K - 1, Draw).

boids() ->
    [Pid || {_, Pid, _, _} <- supervisor:which_children(boid_sup)].

snapshot() ->
    [gen_server:call(Pid, get_state) || Pid <- boids()].

%%--------------------------------------------------------------------
draw(Snapshot) ->
    Grid0 = maps:from_list([{{Cx, Cy}, $\s}
                            || Cx <- lists:seq(0, ?W - 1),
                               Cy <- lists:seq(0, ?H - 1)]),
    Grid = lists:foldl(
             fun({_, X, Y, VX, VY}, G) ->
                     Cx = min(trunc(X), ?W - 1),
                     Cy = min(trunc(Y), ?H - 1),
                     maps:put({Cx, Cy}, glyph(VX, VY), G)
             end, Grid0, Snapshot),
    io:format("\e[H\e[2J", []),   % clear screen (no-op in logs)
    Border = lists:duplicate(?W, $-),
    io:format("+~s+~n", [Border]),
    [io:format("|~s|~n",
               [[maps:get({Cx, Cy}, Grid) || Cx <- lists:seq(0, ?W - 1)]])
     || Cy <- lists:seq(0, ?H - 1)],
    io:format("+~s+~n", [Border]).

%% direction glyph from velocity
glyph(VX, VY) ->
    A = math:atan2(VY, VX),
    Oct = trunc((A + math:pi()) / (math:pi() / 4)) rem 8,
    lists:nth(Oct + 1, "<\\v/>/^\\").
