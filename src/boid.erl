%%% boid.erl — a single boid as an isolated Erlang process.
%%% Each boid holds its own position/velocity and reacts to a snapshot
%%% of its neighbours. If it crashes, the supervisor restarts it at a
%%% random position — the flock never dies.
-module(boid).
-behaviour(gen_server).

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(W, 80.0).            % world width
-define(H, 24.0).            % world height
-define(PERCEPTION, 10.0).   % neighbour radius
-define(SEP_RADIUS, 2.5).    % separation radius
-define(MAX_SPEED, 1.2).
-define(MIN_SPEED, 0.4).
-define(W_SEP, 0.08).
-define(W_ALI, 0.05).
-define(W_COH, 0.015).

-record(s, {x, y, vx, vy}).

%%--------------------------------------------------------------------
start_link(Id) ->
    gen_server:start_link(?MODULE, Id, []).

init(_Id) ->
    X  = rand:uniform() * ?W,
    Y  = rand:uniform() * ?H,
    A  = rand:uniform() * 2 * math:pi(),
    Sp = ?MIN_SPEED + rand:uniform() * (?MAX_SPEED - ?MIN_SPEED),
    {ok, #s{x = X, y = Y, vx = Sp * math:cos(A), vy = Sp * math:sin(A)}}.

%%--------------------------------------------------------------------
handle_call(get_state, _From, S = #s{x = X, y = Y, vx = VX, vy = VY}) ->
    {reply, {self(), X, Y, VX, VY}, S}.

%% Neighbours is a snapshot of every boid: [{Pid, X, Y, VX, VY}]
handle_cast({tick, Neighbours}, S) ->
    {noreply, step(S, Neighbours)}.

handle_info(_, S) -> {noreply, S}.

%%--------------------------------------------------------------------
%% Classic Reynolds rules: separation, alignment, cohesion.
step(#s{x = X, y = Y, vx = VX, vy = VY}, All) ->
    Near = [{NX, NY, NVX, NVY}
            || {Pid, NX, NY, NVX, NVY} <- All,
               Pid =/= self(),
               dist(X, Y, NX, NY) < ?PERCEPTION],
    {AX, AY} = case Near of
                   []    -> {0.0, 0.0};
                   [_|_] -> steer(X, Y, VX, VY, Near)
               end,
    VX1 = VX + AX,
    VY1 = VY + AY,
    {VX2, VY2} = clamp_speed(VX1, VY1),
    #s{x = wrap(X + VX2, ?W), y = wrap(Y + VY2, ?H), vx = VX2, vy = VY2}.

steer(X, Y, VX, VY, Near) ->
    N = length(Near),
    %% cohesion: towards centre of mass
    {CX, CY} = fold2(fun({NX, NY, _, _}, {Ax, Ay}) -> {Ax + NX, Ay + NY} end, Near),
    Coh = {(CX / N - X) * ?W_COH, (CY / N - Y) * ?W_COH},
    %% alignment: match average velocity
    {AVX, AVY} = fold2(fun({_, _, NVX, NVY}, {Ax, Ay}) -> {Ax + NVX, Ay + NVY} end, Near),
    Ali = {(AVX / N - VX) * ?W_ALI, (AVY / N - VY) * ?W_ALI},
    %% separation: push away from very close neighbours
    Sep = fold2(fun({NX, NY, _, _}, {Ax, Ay}) ->
                        D = max(dist(X, Y, NX, NY), 0.01),
                        case D < ?SEP_RADIUS of
                            true  -> {Ax + (X - NX) / (D * D), Ay + (Y - NY) / (D * D)};
                            false -> {Ax, Ay}
                        end
                end, Near),
    {SepX, SepY} = Sep,
    {CohX, CohY} = Coh,
    {AliX, AliY} = Ali,
    {SepX * ?W_SEP + CohX + AliX, SepY * ?W_SEP + CohY + AliY}.

fold2(F, L) -> lists:foldl(F, {0.0, 0.0}, L).

dist(X1, Y1, X2, Y2) ->
    DX = X1 - X2, DY = Y1 - Y2,
    math:sqrt(DX * DX + DY * DY).

clamp_speed(VX, VY) ->
    Sp = math:sqrt(VX * VX + VY * VY),
    if Sp > ?MAX_SPEED -> {VX / Sp * ?MAX_SPEED, VY / Sp * ?MAX_SPEED};
       Sp < ?MIN_SPEED andalso Sp > 0.0 ->
           {VX / Sp * ?MIN_SPEED, VY / Sp * ?MIN_SPEED};
       true -> {VX, VY}
    end.

wrap(V, Max) when V < 0    -> V + Max;
wrap(V, Max) when V >= Max -> V - Max;
wrap(V, _)                 -> V.
