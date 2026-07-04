# Boids on the BEAM

Craig Reynolds' boids, where **every boid is an isolated Erlang process**
(`gen_server`) under a `simple_one_for_one` supervisor. Zero external
dependencies — pure OTP.

Instead of a compute shader updating a buffer of structs, each boid owns its
state and reacts to message-passed snapshots of the flock. Kill any boid
mid-flight — the supervisor restarts it and the flock never notices.

## Architecture

```
boid_sup (simple_one_for_one)
 ├── boid #1   gen_server: {x, y, vx, vy}
 ├── boid #2
 ├── ...
 └── boid #N

flock (coordinator)
  every tick: snapshot = call(get_state) from all boids
              cast({tick, snapshot}) to all boids
              render ASCII frame
```

Rules per boid (classic Reynolds): separation, alignment, cohesion.
Toroidal 80×24 world, direction glyphs `< > ^ v / \` in the terminal.

## Run

```bash
erlc -o ebin src/*.erl
erl -pa ebin
```

```erlang
1> flock:run().          % 60 boids, 300 animated frames
2> flock:chaos().        % kill a random boid — watch the supervisor
```

Non-interactive check:

```bash
erl -noshell -pa ebin -eval "flock:demo()"
```

`demo/0` renders two frames and proves fault tolerance:

```
killing boid <0.110.0>...
boids before kill: 60, after supervisor restart: 60
```

## Why this is interesting

- **1 boid = 1 process.** BEAM processes cost ~2 KB; 10 000 boids is trivial
  for the runtime (the O(N²) neighbour search becomes the limit, not the
  processes).
- **Fault tolerance for free.** `exit(Pid, kill)` on any boid → supervisor
  restarts it at a random position within microseconds.
- **The opposite of GPU boids.** No shared memory, no buffers — only
  message passing. A useful contrast to compute-shader implementations.

Tested on Erlang/OTP 25.
