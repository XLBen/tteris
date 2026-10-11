// The effects of the "Pixel FX" resource pack, one per game event, and the
// two loops of the default pack: the backdrop behind everything and the
// animated title (kinds 'backdrop' and 'title').
//
// Sizes are art pixels: a board cell is CELL (11) of them, so a sheet drawn at
// scale 2 lines up with the game's 22-pixel cells. Every effect is a timeline
// (see `phases`) that ends on an empty frame: anticipation, ignition, burst,
// decay - with the particles each phase gives birth to living on into the
// next ones.
(function (root) {
	'use strict';
	const FX = root.PixelFX || require('./fx_core.js');
	const { ease, lerp, clamp01, bolt, makeRng } = FX;

	const CELL = 11;
	const TAU = Math.PI * 2;
	const hexes = (list) => list.map(FX.hex);
	const WHITE = [1, 1, 1, 1];
	const PIECES = hexes(['#33d9f2', '#f2cc40', '#bf66f2', '#66e680', '#f27373', '#598cf2', '#f29e47']);
	const ICE = hexes(['#ffffff', '#c8f8ff', '#78e4fc', '#30b8f4']);
	const GREYS = hexes(['#c8ced6', '#8c949e', '#5a6068']);
	const GOLDS = hexes(['#ffffff', '#fff8c8', '#fce070', '#f8bc28']);

	// ------------------------------------------------------------- emitters
	function sparks(sim, layer, x, y, count, o) {
		o = o || {};
		const r = sim.rng;
		sim.burst(count, () => {
			const a = o.angle ? r.range(o.angle[0], o.angle[1]) : r.angle();
			const s = r.range(o.speed ? o.speed[0] : 40, o.speed ? o.speed[1] : 140);
			return {
				layer,
				x: x + (o.spread ? r.range(-o.spread, o.spread) : 0),
				y: y + (o.spreadY ? r.range(-o.spreadY, o.spreadY) : 0),
				vx: Math.cos(a) * s,
				vy: Math.sin(a) * s * (o.sy || 1),
				life: r.range(o.life ? o.life[0] : 0.2, o.life ? o.life[1] : 0.5),
				gravity: o.gravity || 0,
				drag: o.drag === undefined ? 2.5 : o.drag,
				streak: o.streak === undefined ? 0.03 : o.streak,
				heat: o.heat || [1, 0.25],
			};
		});
	}

	// Solid colored chips: thrown, pulled down, bouncing, blinking out.
	function debris(sim, layer, x, y, count, o) {
		const r = sim.rng;
		sim.burst(count, () => ({
			layer,
			x: x + r.range(-(o.spread || 0), o.spread || 0),
			y: y + r.range(-(o.spreadY || 0), o.spreadY || 0),
			vx: r.range(-o.vx, o.vx),
			vy: r.range(o.vy[0], o.vy[1]),
			gravity: o.gravity === undefined ? 480 : o.gravity,
			floor: o.floor,
			bounce: o.bounce === undefined ? 0.45 : o.bounce,
			life: r.range(o.life[0], o.life[1]),
			color: r.pick(o.colors),
			size: r.pick(o.sizes || [1, 1, 2]),
			blink: o.blink === undefined ? 0.7 : o.blink,
		}));
	}

	// Soft blobs that swell, drift and thin out (smoke, dust).
	function puffs(sim, layer, count, make) {
		const r = sim.rng;
		sim.burst(count, (i) => {
			const p = make(i, r);
			return Object.assign({ layer, drag: 2, soft: 0.5, heat: [0.95, 0.1], life: r.range(0.4, 0.8) }, p);
		});
	}

	// Slow glowing motes that wander upward and flicker.
	function embers(sim, layer, count, box, o) {
		o = o || {};
		const r = sim.rng;
		sim.burst(count, () => {
			const phase = r.angle();
			return {
				layer,
				x: r.range(box[0], box[2]),
				y: r.range(box[1], box[3]),
				vx: r.range(-12, 12),
				vy: r.range(-55, -20),
				turb: 150,
				drag: 0.8,
				life: r.range(o.life ? o.life[0] : 0.35, o.life ? o.life[1] : 0.6),
				size: 0.5,
				heat: (k) => (1 - k) * (0.65 + 0.35 * Math.sin(k * 50 + phase)),
			};
		});
	}

	// Four-armed twinkles that open and close.
	function stars(sim, layer, count, box, o) {
		o = o || {};
		const r = sim.rng;
		sim.burst(count, () => {
			const arm = r.pick(o.arms || [1, 2, 2, 3]);
			const delay = r.range(0, o.delay || 0.2);
			const life = delay + r.range(0.2, 0.36);
			return {
				layer,
				shape: 'star',
				x: r.range(box[0], box[2]),
				y: r.range(box[1], box[3]),
				delay,
				life,
				color: r.pick(o.colors || ICE),
				size: (k) => arm * ease.bell((k * life - delay) / (life - delay)),
			};
		});
	}

	// Streaks rushing in toward a point: the breath before the bang.
	function converge(sim, layer, cx, cy, count, o) {
		const r = sim.rng;
		sim.burst(count, () => {
			const a = r.angle();
			const radius = r.range(o.radius[0], o.radius[1]);
			const life = r.range(o.life[0], o.life[1]);
			return {
				layer,
				x: cx + Math.cos(a) * radius,
				y: cy + Math.sin(a) * radius * (o.sy || 1),
				vx: (-Math.cos(a) * radius) / life,
				vy: (-Math.sin(a) * radius * (o.sy || 1)) / life,
				life,
				drag: 0,
				streak: 0.045,
				heat: [0.25, 1],
			};
		});
	}

	const defs = [];
	const define = (def) => defs.push(def);

	// ----------------------------------------------------------------- lock
	define({
		name: 'lock',
		title: 'Lock',
		note: 'A piece settles: a quick glint, a thin ring and a few sparks. Played at the piece.',
		w: 40, h: 40, frames: 8, anchor: 'center', seed: 11,
		phases: [{ name: 'glint', at: 0 }, { name: 'ring', at: 0.05 }, { name: 'fade', at: 0.16 }],
		setup(sim) {
			sim.layer('ring', { ramp: 'white' });
			sim.layer('sparks', { ramp: 'plasma' });
		},
		update(sim) {
			if (sim.once('sparks', 0)) sparks(sim, sim.byName.sparks, 20, 20, 7, { speed: [30, 80], life: [0.1, 0.22], streak: 0.02 });
		},
		draw(sim, t) {
			const ring = sim.byName.ring;
			if (t < 0.08) ring.disc(20, 20, 5, 0.9 * (1 - sim.k(0, 0.08)), 0.8);
			const k = sim.k(0.02, 0.25);
			if (k < 1) ring.ring(20, 20, lerp(3, 16, ease.outCubic(k)), lerp(3, 1, k), 0.9 * (1 - k));
		},
	});

	// ------------------------------------------------------------ hard drop
	define({
		name: 'hard_drop',
		title: 'Hard drop',
		note: 'A piece slams down: a flash along the floor, dust rolling out to both sides, sparks and chips. Bottom-anchored under the piece.',
		w: 112, h: 48, frames: 14, anchor: 'bottom', seed: 23,
		phases: [{ name: 'impact', at: 0 }, { name: 'spread', at: 0.07 }, { name: 'settle', at: 0.25 }],
		setup(sim) {
			sim.layer('dust', { ramp: 'dust', erode: { amount: (t) => t * 1.7, scale: 0.2, speed: 2 } });
			sim.layer('chips', { kind: 'color' });
			sim.layer('sparks', { ramp: 'gold' });
			sim.layer('flash', { ramp: 'white' });
		},
		update(sim) {
			if (!sim.once('impact', 0)) return;
			const floor = 45;
			for (const side of [-1, 1]) {
				puffs(sim, sim.byName.dust, 7, (i, r) => ({
					x: 56 + side * r.range(2, 16), y: floor - r.range(0, 3),
					vx: side * r.range(40, 115), vy: -r.range(4, 24), drag: 4.5,
					life: r.range(0.3, 0.45), size: [2.5, r.range(5, 8)], heat: [0.95, 0.2],
				}));
			}
			sparks(sim, sim.byName.sparks, 56, floor - 1, 16, { angle: [-Math.PI * 0.9, -Math.PI * 0.1], speed: [60, 160], gravity: 320, life: [0.14, 0.34], spread: 18 });
			debris(sim, sim.byName.chips, 56, floor - 2, 9, { spread: 18, vx: 90, vy: [-150, -50], gravity: 520, floor, bounce: 0.4, life: [0.25, 0.44], colors: GREYS.concat([WHITE]), blink: 0.6 });
		},
		draw(sim, t) {
			if (t < 0.1) {
				const k = sim.k(0, 0.1);
				sim.byName.flash.rect(56 - 26 * (1 - k * 0.5), 44, 56 + 26 * (1 - k * 0.5), 46, 1 - k);
				sim.byName.flash.disc(56, 44, 9 * (1 - k), 0.8 * (1 - k), 1, 0.45);
			}
		},
	});

	// -------------------------------------------------------------- garbage
	define({
		name: 'garbage',
		title: 'Garbage',
		note: 'Garbage rows push in from below: a warning glint runs along the floor, grit jumps, dust rises. Bottom-anchored on the board.',
		w: 128, h: 44, frames: 14, anchor: 'bottom', seed: 37,
		phases: [{ name: 'glint', at: 0 }, { name: 'rumble', at: 0.05 }, { name: 'settle', at: 0.26 }],
		setup(sim) {
			sim.layer('dust', { ramp: 'smoke', erode: { amount: (t) => t * 1.5, scale: 0.2, speed: 2 } });
			sim.layer('grit', { kind: 'color' });
			sim.layer('glint', { ramp: 'fire' });
		},
		update(sim) {
			if (!sim.once('rumble', 0.03)) return;
			const floor = 41;
			puffs(sim, sim.byName.dust, 22, (i, r) => ({
				x: r.range(9, 119), y: floor - r.range(0, 3), vx: r.range(-18, 18), vy: -r.range(25, 75), drag: 3.2,
				life: r.range(0.24, 0.42), size: [2, r.range(4.5, 7)], heat: [0.95, 0.1],
			}));
			debris(sim, sim.byName.grit, 64, floor - 1, 28, { spread: 55, vx: 32, vy: [-175, -60], gravity: 540, floor, bounce: 0.3, life: [0.22, 0.42], colors: GREYS, blink: 0.6 });
		},
		draw(sim, t) {
			const glint = sim.byName.glint;
			const k = sim.k(0, 0.22);
			if (k < 1) {
				glint.rect(9, 41, 119, 43, 0.85 * (1 - k));
				for (const side of [-1, 1]) glint.disc(64 + side * 55 * ease.outCubic(k), 41, 3.5 * (1 - k * 0.5), 1 - k * 0.6, 0.6);
			}
		},
	});

	// ----------------------------------------------------------- line clear
	define({
		name: 'line_clear',
		title: 'Line clear',
		note: 'One per cleared row (1-3 lines): the row whitens, a plasma beam splits it from the middle, then it breaks into shards and sparks and is eaten away.',
		w: 144, h: 40, frames: 18, anchor: 'center', seed: 41,
		phases: [{ name: 'charge', at: 0 }, { name: 'split', at: 0.07 }, { name: 'shatter', at: 0.2 }, { name: 'embers', at: 0.38 }],
		setup(sim) {
			sim.layer('trail', { ramp: 'plasma', persist: 0.88 });
			sim.layer('energy', { ramp: 'plasma', outline: '#061040c0', erode: { amount: (t) => Math.max(0, t - 0.12) * 3.2, scale: 0.16, speed: 3 } });
			sim.layer('shards', { kind: 'color' });
			sim.layer('sparks', { ramp: 'plasma' });
			sim.layer('flash', { ramp: 'white' });
		},
		update(sim, t) {
			const L = sim.byName;
			if (sim.during(0.05, 0.2)) {
				const reach = 55 * ease.outCubic(sim.k(0.05, 0.2));
				for (const side of [-1, 1]) {
					const x = 72 + side * reach;
					L.trail.disc(x, 20, 3, 0.8, 0.5);
					sparks(sim, L.sparks, x, 20, 1, { angle: side > 0 ? [-1.2, 1.2] : [Math.PI - 1.2, Math.PI + 1.2], speed: [30, 100], life: [0.12, 0.26], spreadY: 4 });
				}
			}
			if (sim.once('shatter', 0.07)) {
				debris(sim, L.shards, 72, 20, 24, { spread: 55, spreadY: 5, vx: 125, vy: [-150, 40], gravity: 420, life: [0.25, 0.48], colors: ICE, blink: 0.65 });
				sparks(sim, L.sparks, 72, 20, 40, { spread: 55, spreadY: 5, speed: [30, 125], life: [0.14, 0.38] });
			}
			if (sim.once('embers', 0.24)) embers(sim, L.sparks, 10, [17, 14, 127, 26], { life: [0.2, 0.33] });
		},
		draw(sim, t) {
			const L = sim.byName;
			if (t < 0.07) {
				const k = sim.k(0, 0.07);
				L.flash.rect(17, 14, 127, 25, 0.6 * k);
				L.energy.beam(72 - 58 * k, 72 + 58 * k, 19.5, 1.5 + k, 1);
				return;
			}
			const half = lerp(5.5, 1.5, ease.in(sim.k(0.2, 0.55)));
			const heat = lerp(1, 0.55, sim.k(0.07, 0.6)) * (1 - ease.in(sim.k(0.38, 0.56)));
			if (heat > 0) L.energy.beam(11, 133, 19.5, half + 1, heat);
			if (t < 0.14) L.flash.beam(9, 135, 19.5, 8 * (1 - 0.5 * sim.k(0.07, 0.14)), 1 - sim.k(0.07, 0.14));
			if (sim.during(0.05, 0.22)) {
				const reach = 55 * ease.outCubic(sim.k(0.05, 0.2));
				for (const side of [-1, 1]) L.flash.disc(72 + side * reach, 20, 4.5 * (1 - sim.k(0.16, 0.22)), 1, 0.4);
			}
		},
	});

	// --------------------------------------------------------------- tetris
	define({
		name: 'tetris',
		title: 'Tetris',
		note: 'Four rows at once: light is drawn in, the block flashes with a star, four beams tear outward under two shock rings and crackling arcs, and the glitter hangs for a moment.',
		w: 176, h: 128, frames: 30, anchor: 'center', seed: 53,
		phases: [{ name: 'gather', at: 0 }, { name: 'flash', at: 0.13 }, { name: 'burst', at: 0.2 }, { name: 'arcs', at: 0.28 }, { name: 'glitter', at: 0.5 }],
		setup(sim) {
			sim.layer('trail', { ramp: 'plasma', persist: 0.9 });
			sim.layer('energy', { ramp: 'plasma', outline: '#061040c0', erode: { amount: (t) => Math.max(0, t - 0.28) * 2.5, scale: 0.11, speed: 2.5 } });
			sim.layer('ring', { ramp: 'plasma' });
			sim.layer('shards', { kind: 'color' });
			sim.layer('sparks', { ramp: 'plasma' });
			sim.layer('arcs', { ramp: 'white', dither: 0 });
			sim.layer('stars', { kind: 'color' });
			sim.layer('flash', { ramp: 'white' });
		},
		update(sim, t) {
			const L = sim.byName;
			if (sim.once('gather', 0)) converge(sim, L.sparks, 88, 64, 28, { radius: [60, 86], life: [0.13, 0.19], sy: 0.6 });
			if (sim.once('burst', 0.2)) {
				sparks(sim, L.sparks, 88, 64, 115, { spread: 55, spreadY: 22, speed: [60, 230], life: [0.2, 0.6], drag: 2.2, gravity: 60 });
				debris(sim, L.shards, 88, 64, 46, { spread: 55, spreadY: 22, vx: 175, vy: [-230, 60], gravity: 480, life: [0.32, 0.7], colors: PIECES.concat(ICE), sizes: [1, 2, 2] });
				for (const p of sim.parts) if (p.layer === L.sparks && sim.rng() < 0.3) { p.trail = L.trail; p.trailHeat = [0.6, 0.1]; }
			}
			if (sim.during(0.2, 0.52) && sim.ticks % 3 === 0) sim.state.arcSeed = sim.rng.int(1, 1e6);
			if (sim.once('glitter', 0.46)) {
				stars(sim, L.stars, 13, [20, 28, 156, 100], { delay: 0.22 });
				embers(sim, L.sparks, 22, [33, 42, 143, 86], { life: [0.3, 0.5] });
			}
		},
		draw(sim, t) {
			const L = sim.byName;
			if (t < 0.13) {
				const k = sim.k(0, 0.13);
				for (let row = 0; row < 4; row++) {
					const y = 42 + row * CELL + 5.5;
					L.energy.beam(88 - 58 * k, 88 + 58 * k, y, 1 + k, 0.45 + 0.5 * k);
				}
				return;
			}
			if (t < 0.22) {
				const k = sim.k(0.13, 0.22);
				for (let row = 0; row < 4; row++) L.flash.beam(24, 152, 42 + row * CELL + 5.5, 7, 1 - k * 0.6);
				const reach = ease.outExpo(k);
				L.flash.line(88 - 86 * reach, 64, 88 + 86 * reach, 64, 1);
				L.flash.line(88, 64 - 60 * reach, 88, 64 + 60 * reach, 1);
				L.flash.line(88 - 40 * reach, 64 - 28 * reach, 88 + 40 * reach, 64 + 28 * reach, 0.8);
				L.flash.line(88 - 40 * reach, 64 + 28 * reach, 88 + 40 * reach, 64 - 28 * reach, 0.8);
			}
			if (t >= 0.2) {
				const ext = 16 * ease.outCubic(sim.k(0.2, 0.32));
				const half = lerp(5.5, 1.2, ease.in(sim.k(0.34, 0.88)));
				const heat = lerp(1, 0.6, sim.k(0.2, 1)) * (1 - ease.in(sim.k(0.7, 0.95)));
				if (heat > 0) {
					for (let row = 0; row < 4; row++) {
						const y = 42 + row * CELL + 5.5;
						L.energy.beam(29 - ext, 147 + ext, y, half + 0.6, heat);
					}
				}
				for (const [from, to, reach] of [[0.2, 0.55, 98], [0.27, 0.7, 80]]) {
					const k = sim.k(from, to);
					if (t >= from && k < 1) L.ring.ring(88, 64, lerp(8, reach, ease.outCubic(k)), lerp(7, 1.5, k), 1 - k, 0.62);
				}
			}
			if (sim.during(0.2, 0.52) && sim.state.arcSeed) {
				const r = makeRng(sim.state.arcSeed);
				for (let i = 0; i < 3; i++) bolt(L.arcs, r, 30, r.range(44, 84), 146, r.range(44, 84), 12, 0.95);
			}
		},
	});

	// --------------------------------------------------------------- t-spin
	const T_CELLS = [[-1, 0], [0, 0], [1, 0], [0, -1]];
	define({
		name: 'tspin',
		title: 'T-spin',
		note: 'Three arms of light spiral into the slot, the T snaps in as a white stamp, and the spin is thrown back out as a ring and a swirl of sparks.',
		w: 96, h: 96, frames: 24, anchor: 'center', seed: 67,
		phases: [{ name: 'wind-up', at: 0 }, { name: 'snap', at: 0.2 }, { name: 'throw', at: 0.27 }, { name: 'fade', at: 0.55 }],
		setup(sim) {
			sim.layer('trail', { ramp: 'arcane', persist: 0.9 });
			sim.layer('energy', { ramp: 'arcane', outline: '#18063cc0', erode: { amount: (t) => Math.max(0, t - 0.3) * 2.4, scale: 0.14, speed: 3 } });
			sim.layer('ring', { ramp: 'arcane' });
			sim.layer('sparks', { ramp: 'arcane' });
			sim.layer('stars', { kind: 'color' });
			sim.layer('flash', { ramp: 'white' });
		},
		update(sim) {
			const L = sim.byName;
			const r = sim.rng;
			if (sim.once('arms', 0)) {
				for (let arm = 0; arm < 3; arm++) {
					for (let i = 0; i < 9; i++) {
						const radius = 42 - i * 1.6;
						sim.emit({
							layer: L.sparks, x: 48, y: 48, life: 0.21, size: 1.2, heat: [0.5, 1],
							angle: (arm * TAU) / 3 + i * 0.22, radius, shrink: radius / 0.2,
							trail: L.trail, trailHeat: 0.85,
							move(p, dt) {
								p.angle += 9 * dt;
								p.radius = Math.max(0, p.radius - p.shrink * dt);
								p.x = 48 + Math.cos(p.angle) * p.radius;
								p.y = 48 + Math.sin(p.angle) * p.radius;
							},
						});
					}
				}
			}
			if (sim.once('throw', 0.2)) {
				sim.burst(56, () => {
					const a = r.angle(), s = r.range(50, 155);
					return {
						layer: L.sparks, x: 48 + Math.cos(a) * 6, y: 48 + Math.sin(a) * 6,
						vx: Math.cos(a) * s - Math.sin(a) * s * 0.8, vy: Math.sin(a) * s + Math.cos(a) * s * 0.8,
						life: r.range(0.24, 0.55), drag: 2.6, streak: 0.035, heat: [1, 0.2],
					};
				});
				stars(sim, L.stars, 9, [12, 12, 84, 84], { delay: 0.28, colors: hexes(['#ffffff', '#f4dcff', '#dc98fc']) });
			}
		},
		draw(sim, t) {
			const L = sim.byName;
			if (t < 0.2) {
				const k = sim.k(0, 0.2);
				L.energy.disc(48, 48, 2 + 5 * k, 0.6 + 0.4 * k, 0.5);
				return;
			}
			const stamp = (layer, heat, grow) => {
				for (const [cx, cy] of T_CELLS) layer.rect(48 + cx * CELL - 5.5 - grow, 48 + cy * CELL - grow, 48 + cx * CELL + 5.5 + grow, 48 + cy * CELL + CELL + grow, heat);
			};
			if (t < 0.3) stamp(L.flash, 1 - sim.k(0.2, 0.3), 1);
			const heat = lerp(1, 0.5, sim.k(0.2, 0.8)) * (1 - ease.in(sim.k(0.52, 0.76)));
			if (heat > 0) stamp(L.energy, heat, 0);
			const k = sim.k(0.22, 0.6);
			if (k < 1) L.ring.ring(48, 48, lerp(6, 45, ease.outCubic(k)), lerp(6, 1.5, k), 1 - k);
		},
	});

	// -------------------------------------------------------- perfect clear
	define({
		name: 'perfect_clear',
		title: 'Perfect clear',
		note: 'The empty board answers: motes gather, a cross of light opens, three rings roll out, a golden curtain rises from the floor and confetti rains through the twinkles.',
		w: 160, h: 232, frames: 42, anchor: 'center', seed: 79,
		phases: [{ name: 'gather', at: 0 }, { name: 'flare', at: 0.2 }, { name: 'rings', at: 0.28 }, { name: 'curtain', at: 0.3 }, { name: 'shower', at: 0.45 }, { name: 'fade', at: 1.0 }],
		setup(sim) {
			sim.layer('curtain', { ramp: 'gold', fire: { cooling: 0.016, speed: 3, row: 225 } });
			sim.layer('trail', { ramp: 'gold', persist: 0.9 });
			sim.layer('ring', { ramp: 'gold' });
			sim.layer('energy', { ramp: 'gold', outline: '#3c1c04c0' });
			sim.layer('sparks', { ramp: 'gold' });
			sim.layer('confetti', { kind: 'color' });
			sim.layer('stars', { kind: 'color' });
			sim.layer('flash', { ramp: 'white' });
		},
		update(sim, t) {
			const L = sim.byName;
			const r = sim.rng;
			if (sim.once('gather', 0)) converge(sim, L.sparks, 80, 116, 42, { radius: [50, 80], life: [0.14, 0.2], sy: 1.4 });
			const fuel = sim.during(0.3, 0.72) ? 1 - 0.55 * sim.k(0.3, 0.72) : 0;
			for (let x = 25; x < 135; x++) L.curtain.fuel[x] = fuel;
			if (sim.once('burst', 0.24)) {
				sparks(sim, L.sparks, 80, 116, 95, { speed: [60, 240], sy: 1.3, life: [0.3, 0.7], drag: 2.2 });
				for (const p of sim.parts) if (p.layer === L.sparks && r() < 0.35) { p.trail = L.trail; p.trailHeat = [0.6, 0.1]; }
			}
			if (sim.during(0.45, 1.0) && sim.ticks % 2 === 0) {
				debris(sim, L.confetti, 80, 30, 2, { spread: 55, spreadY: 26, vx: 22, vy: [30, 85], gravity: 90, life: [0.4, 0.62], colors: PIECES.concat(GOLDS), sizes: [1, 1, 2], blink: 0.75 });
				for (const p of sim.parts) if (p.layer === L.confetti) p.turb = 90;
			}
			if (sim.once('stars', 0.48)) stars(sim, L.stars, 24, [22, 10, 138, 222], { delay: 0.5, colors: GOLDS });
		},
		draw(sim, t) {
			const L = sim.byName;
			if (t < 0.2) {
				const k = sim.k(0, 0.2);
				L.energy.disc(80, 116, 3 + 6 * k, 0.5 + 0.5 * k, 0.5);
			} else if (t < 0.34) {
				const k = sim.k(0.2, 0.34);
				const wide = lerp(9, 0.5, k);
				L.flash.beam(8, 152, 116, wide, 1 - k * 0.4);
				L.flash.beam(4, 228, 80, wide, 1 - k * 0.4, true);
				L.energy.disc(80, 116, 15 * (1 - k * 0.6), 1, 0.5);
			}
			for (const start of [0.28, 0.4, 0.52]) {
				const k = sim.k(start, start + 0.46);
				if (t >= start && k < 1) L.ring.ring(80, 116, lerp(6, 74, ease.outCubic(k)), lerp(8, 1.5, k), 1 - k, 1.45);
			}
		},
	});

	// ------------------------------------------------------------------- KO
	// The showpiece: every component in one timeline.
	define({
		name: 'ko',
		title: 'K.O. detonation',
		note: 'The board is lost: light is sucked into the core, it ignites white, a fireball swells and is eaten into puffs while it rises, a shock ring races along the ground, the pieces are thrown as chips that bounce on the floor, a wall of flame climbs from the rubble, and smoke and embers carry it out.',
		w: 176, h: 240, frames: 45, anchor: 'center', seed: 97,
		phases: [{ name: 'inhale', at: 0 }, { name: 'ignition', at: 0.2 }, { name: 'fireball', at: 0.27 }, { name: 'flames', at: 0.3 }, { name: 'smoke', at: 0.6 }, { name: 'embers', at: 0.95 }],
		setup(sim) {
			sim.layer('smoke', { ramp: 'smoke', erode: { amount: (t) => 0.2 + Math.max(0, t - 0.6) * 0.95, scale: 0.09, speed: 1.2 } });
			sim.layer('flames', { ramp: 'fire', fire: { cooling: 0.034, speed: 2, row: 229 } });
			sim.layer('fireball', { ramp: 'fire', outline: '#200808d0', erode: { amount: (t) => Math.max(0, t - 0.3) * 2.3, scale: 0.08, speed: 2.2 } });
			sim.layer('ring', { ramp: 'white' });
			sim.layer('chips', { kind: 'color' });
			sim.layer('embers', { ramp: 'ember', dither: 0 });
			sim.layer('sparks', { ramp: 'gold' });
			sim.layer('flash', { ramp: 'white' });
		},
		update(sim, t) {
			const L = sim.byName;
			const r = sim.rng;
			if (sim.once('inhale', 0)) converge(sim, L.sparks, 88, 128, 36, { radius: [70, 112], life: [0.15, 0.2] });
			if (sim.once('ignition', 0.2)) {
				sim.state.blobs = [];
				for (let i = 0; i < 9; i++) sim.state.blobs.push({ dx: i === 0 ? 0 : r.range(-22, 22), dy: i === 0 ? 0 : r.range(-22, 22), radius: i === 0 ? 40 : r.range(24, 40), delay: r.range(0, 0.06) });
				sparks(sim, L.sparks, 88, 128, 150, { speed: [80, 300], life: [0.25, 0.7], gravity: 120, drag: 2, streak: 0.035 });
				debris(sim, L.chips, 88, 128, 72, { spread: 30, spreadY: 30, vx: 225, vy: [-330, 40], gravity: 620, floor: 229, bounce: 0.45, life: [0.7, 1.22], colors: PIECES, sizes: [1, 2, 2, 3], blink: 0.8 });
				puffs(sim, L.smoke, 16, (i, rr) => ({
					x: 88 + rr.range(-26, 26), y: 128 + rr.range(-24, 24), vx: rr.range(-26, 26), vy: -rr.range(20, 60), turb: 50, drag: 1.4,
					delay: rr.range(0.1, 0.3), life: rr.range(0.9, 1.25), size: [5, rr.range(12, 18)], heat: [1, 0.35], soft: 0.4,
				}));
			}
			const fuel = sim.during(0.3, 0.95) ? 1 - sim.k(0.3, 0.95) : 0;
			for (let x = 40; x < 136; x++) {
				const d = (x - 88) / 55;
				L.flames.fuel[x] = fuel * (1 - 0.5 * d * d);
			}
			if (sim.during(0.5, 0.95) && sim.ticks % 3 === 0) embers(sim, L.embers, 2, [45, 150, 131, 228], { life: [0.35, 0.5] });
			if (sim.once('smoke', 0.62)) {
				puffs(sim, L.smoke, 10, (i, rr) => ({
					x: 88 + rr.range(-44, 44), y: 205 + rr.range(-14, 14), vx: rr.range(-14, 14), vy: -rr.range(30, 70), turb: 60, drag: 1.2,
					life: rr.range(0.6, 0.85), size: [4, rr.range(9, 14)], heat: [0.9, 0.3], soft: 0.4,
				}));
			}
		},
		draw(sim, t) {
			const L = sim.byName;
			if (t < 0.2) {
				const k = sim.k(0, 0.2);
				L.fireball.disc(88, 128, 3 + 9 * k + Math.sin(t * 90), 0.55 + 0.45 * k, 0.5);
				return;
			}
			if (t < 0.3) {
				const k = sim.k(0.2, 0.3);
				L.flash.disc(88, 128, 86, 1 - k, 1, 1.3);
				const reach = 110 * ease.outExpo(k);
				for (let i = 0; i < 8; i++) {
					const a = (i * TAU) / 8, len = i % 2 ? reach * 0.6 : reach;
					L.flash.line(88, 128, 88 + Math.cos(a) * len, 128 + Math.sin(a) * len, 1, 0.5);
				}
			}
			const lift = 28 * sim.k(0.3, 1.1);
			const heat = lerp(1, 0.62, sim.k(0.2, 0.9)) * (1 - ease.in(sim.k(0.72, 1.02)));
			if (heat > 0) {
				for (const blob of sim.state.blobs || []) {
					const k = clamp01((t - 0.2 - blob.delay) / 0.3);
					if (k > 0) L.fireball.disc(88 + blob.dx, 128 + blob.dy - lift, blob.radius * ease.outExpo(k), heat, 0.55);
				}
			}
			const k = sim.k(0.2, 0.62);
			if (k < 1) L.ring.ring(88, 150, lerp(10, 128, ease.outCubic(k)), lerp(9, 1.5, k), 1 - k, 0.5);
		},
	});

	const MINOS = [
		[[0, 0], [1, 0], [2, 0], [3, 0]], [[0, 0], [1, 0], [0, 1], [1, 1]], [[0, 0], [1, 0], [2, 0], [1, 1]],
		[[1, 0], [2, 0], [0, 1], [1, 1]], [[0, 0], [1, 0], [1, 1], [2, 1]], [[0, 0], [0, 1], [1, 1], [2, 1]], [[2, 0], [0, 1], [1, 1], [2, 1]],
	];
	const mixColor = (a, b, k) => [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)];
	const BLACK = [0, 0, 0];

	// ------------------------------------------------------------- backdrop
	// The picture behind the menus and the game: a night sky over a skyline of
	// stacked blocks. It is one seamless loop - everything that moves is a
	// function of the loop's phase and comes back to where it started: the
	// aurora drifts on a circle through its noise, every star twinkles a whole
	// number of times, the tetrominoes of three depths fall a whole number of
	// screens, the windows blink in step. Two shooting stars are born, burn
	// their trail and die inside the loop. Kept dark and calm on purpose: the
	// boards and the menus are read on top of it.
	const SKY = hexes(['#060814', '#090d1e', '#0d142c', '#121c3c', '#17254c', '#1c2f5c']);
	const NIGHT = { w: 192, h: 108, loop: 6, fps: 12, cell: 6 };
	FX.RAMPS.aurora = ['#16306a30', '#1c448448', '#22609c5c', '#2c84b068', '#44b0c070', '#7cdcd478'];
	FX.RAMPS.streak = ['#3c68c880', '#78a8f0c0', '#c8e0ff', '#ffffff'];
	const BAYER4 = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((v) => (v + 0.5) / 16);

	define({
		name: 'backdrop',
		kind: 'backdrop',
		title: 'Backdrop',
		note: 'The background of the whole game, one seamless six-second loop: a dithered night sky, an aurora drifting through it, stars that twinkle, tetrominoes falling at three depths, two shooting stars with burning trails, and a skyline of stacked blocks whose windows blink.',
		w: NIGHT.w, h: NIGHT.h, fps: NIGHT.fps, frames: NIGHT.loop * NIGHT.fps, loopFrom: 0, anchor: 'center', seed: 211,
		phases: [{ name: 'first shooting star', at: 0 }, { name: 'calm', at: 2.2 }, { name: 'second shooting star', at: 3.2 }, { name: 'calm, back to the start', at: 5 }],
		setup(sim) {
			sim.layer('sky', { kind: 'color' });
			sim.layer('aurora', { ramp: 'aurora' });
			sim.layer('stars', { kind: 'color' });
			sim.layer('far', { kind: 'color' });
			sim.layer('trail', { ramp: 'streak', persist: 0.9 });
			sim.layer('shooting', { ramp: 'streak', dither: 0 });
			sim.layer('mid', { kind: 'color' });
			sim.layer('near', { kind: 'color' });
			sim.layer('skyline', { kind: 'color' });
			// The cast is fixed once: only the phase moves it.
			const r = makeRng(77);
			const S = sim.state;
			S.stars = [];
			for (let i = 0; i < 90; i++) S.stars.push({ x: r.int(0, NIGHT.w - 1), y: r.int(0, 84), times: r.int(1, 3), phase: r.angle(), big: r() < 0.12, tint: r.pick(ICE) });
			S.minos = [];
			for (const [depth, count, cell, falls] of [[0, 9, 2, 1], [1, 6, 3, 1], [2, 3, 5, 2]]) {
				for (let i = 0; i < count; i++) S.minos.push({ depth, cell, falls, shape: r.int(0, 6), x: r.int(4, NIGHT.w - cell * 4 - 4), start: r.range(0, 1), turn: r.int(0, 3) });
			}
			S.towers = [];
			for (let col = 0; col < NIGHT.w / NIGHT.cell; col++) {
				const height = Math.max(1, Math.round(1 + 2.4 * FX.fbm(col * 0.35, 4.2, 9.1) * 2 + (r() < 0.2 ? 1 : 0)));
				const lights = [];
				for (let row = 0; row < height; row++) if (r() < 0.3) lights.push({ row, times: r.int(1, 2), phase: r.angle() });
				S.towers.push({ height, lights });
			}
		},
		update(sim, t) {
			const L = sim.byName, r = sim.rng;
			for (const [key, at, x, y] of [['one', 0.5, 20, 6], ['two', 3.3, 96, 2]]) {
				if (!sim.once(key, at)) continue;
				sim.emit({ layer: L.shooting, x, y, vx: 96, vy: 42, life: 0.85, size: 0.5, heat: [1, 0.8], trail: L.trail, trailHeat: [1, 0.7],
					onDeath(p, s) { sparks(s, L.shooting, p.x, p.y, 8, { speed: [10, 45], life: [0.2, 0.45], streak: 0 }); } });
			}
			// The trail thins into drifting dust.
			if ((sim.during(0.6, 1.5) || sim.during(3.4, 4.3)) && sim.ticks % 6 === 0) {
				const head = sim.parts.find((p) => p.trail);
				if (head) sim.emit({ layer: L.shooting, x: head.x - r.range(4, 22), y: head.y - r.range(2, 10), vx: r.range(-6, 6), vy: r.range(4, 14), life: r.range(0.3, 0.6), size: 0.5, heat: [0.7, 0] });
			}
		},
		draw(sim, t) {
			const L = sim.byName, S = sim.state;
			const p = ((t / NIGHT.loop) % 1 + 1) % 1;
			const w = NIGHT.w, h = NIGHT.h;
			// Sky: dithered bands, darkest on top.
			for (let y = 0; y < h; y++) {
				for (let x = 0; x < w; x++) {
					const band = (y / h) * (SKY.length - 1) + (BAYER4[(y & 3) * 4 + (x & 3)] - 0.5);
					L.sky.px(x, y, SKY[Math.max(0, Math.min(SKY.length - 1, Math.round(band)))]);
				}
			}
			// Aurora: a ribbon of noise, read along a circle so it returns.
			const ox = Math.cos(p * TAU) * 0.7, oy = Math.sin(p * TAU) * 0.7;
			for (let y = 6; y < 78; y++) {
				const ribbon = Math.sin(((y - 6) / 72) * Math.PI);
				for (let x = 0; x < w; x++) {
					const wave = FX.fbm(x * 0.022 + ox, y * 0.05 + oy + Math.sin(x * 0.05 + p * TAU) * 0.25, 3.7);
					const heat = (wave - 0.44) * 2.6 * ribbon;
					if (heat > 0) L.aurora.plot(x, y, heat);
				}
			}
			for (const star of S.stars) {
				const glow = 0.5 + 0.5 * Math.sin(p * TAU * star.times + star.phase);
				if (glow < 0.22) continue;
				L.stars.px(star.x, star.y, glow > 0.7 ? WHITE : star.tint, 0.35 + 0.65 * glow);
				if (star.big && glow > 0.82) {
					for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) L.stars.px(star.x + dx, star.y + dy, star.tint, 0.6);
				}
			}
			// Tetrominoes: far ones small and faint, near ones large with a bevel.
			const span = h + 40;
			for (const mino of S.minos) {
				const layer = [L.far, L.mid, L.near][mino.depth];
				const tint = mixColor(PIECES[mino.shape], SKY[3], [0.74, 0.64, 0.54][mino.depth]);
				const light = mixColor(tint, WHITE, 0.25), dark = mixColor(tint, BLACK, 0.4);
				const y0 = Math.round(((mino.start + p * mino.falls) % 1) * span) - 24;
				for (let [cx, cy] of MINOS[mino.shape]) {
					for (let q = 0; q < mino.turn; q++) [cx, cy] = [2 - cy, cx];
					for (let j = 0; j < mino.cell; j++) {
						for (let i = 0; i < mino.cell; i++) {
							const edge = mino.depth === 0 ? tint : j === 0 || i === 0 ? light : j === mino.cell - 1 || i === mino.cell - 1 ? dark : tint;
							layer.px(mino.x + cx * mino.cell + i, y0 + cy * mino.cell + j, edge);
						}
					}
				}
			}
			// Skyline: stacked blocks along the bottom, some windows lit.
			const wall = hexes(['#080b1a', '#0c1126', '#141c3a'])
			S.towers.forEach((tower, col) => {
				for (let row = 0; row < tower.height; row++) {
					const x0 = col * NIGHT.cell, y0 = h - (row + 1) * NIGHT.cell;
					for (let j = 0; j < NIGHT.cell; j++) {
						for (let i = 0; i < NIGHT.cell; i++) L.skyline.px(x0 + i, y0 + j, j === 0 || i === 0 ? wall[2] : j === NIGHT.cell - 1 || i === NIGHT.cell - 1 ? wall[0] : wall[1]);
					}
				}
				for (const light of tower.lights) {
					const on = Math.sin(p * TAU * light.times + light.phase);
					if (on < -0.2) continue;
					const x0 = col * NIGHT.cell + 2, y0 = h - (light.row + 1) * NIGHT.cell + 2;
					const lamp = on > 0.5 ? [0.98, 0.82, 0.42] : [0.6, 0.44, 0.2];
					for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) L.skyline.px(x0 + i, y0 + j, lamp);
				}
			});
		},
	});

	// -------------------------------------------------------- backdrop (icon)
	// The backdrop of the "Icon" pack: church domes at dusk under a nimbus.
	// Like the night sky above it is one seamless loop, everything a function
	// of the loop's phase: the nimbus turns by exactly one ray, its rings
	// breathe once, the little crosses in the sky twinkle a whole number of
	// times, the incense rises a whole number of screens, the windows' candles
	// flicker in step.
	const DUSK = hexes(['#090403', '#0f0605', '#170907', '#200c08', '#2b1009', '#38160b', '#461d0d']);
	const LEAF = hexes(['#5a3a10', '#8a5a14', '#c8962e', '#e8b83a', '#ffe27a', '#fff6c8']);
	const DOME_TINTS = hexes(['#e8b83a', '#e8b83a', '#2c50b0', '#e8b83a', '#3c9c62', '#e8b83a', '#b02a1a']);
	const WALL = hexes(['#0c0604', '#160a06', '#26120a']);
	const RAYS = 24;
	// The figures: flesh (light, mid, shade), hair, and the robes' colors.
	const FLESH = hexes(['#d8a878', '#b88458', '#7a4e30']);
	const HAIR = hexes(['#3a2010', '#22120a']);
	const ROBES = { red: hexes(['#a83020', '#7a1e14', '#4e120c']), blue: hexes(['#3a58b8', '#263c8a', '#16245a']), green: hexes(['#3c9c62', '#286e44', '#18442a']) };

	// A filled ellipse; `tone(dx, dy)` (both -1..1) picks each pixel's color.
	function oval(layer, cx, cy, rx, ry, tone) {
		for (let y = Math.ceil(cy - ry); y <= cy + ry; y++) {
			for (let x = Math.ceil(cx - rx); x <= cx + rx; x++) {
				const dx = (x - cx) / rx, dy = (y - cy) / ry;
				if (dx * dx + dy * dy <= 1) layer.px(x, y, tone(dx, dy));
			}
		}
	}

	// A robe: a body widening from the shoulders (`top`) to `bottom`, folds
	// falling as darker lines, a lighter edge on the lit side.
	function robe(layer, cx, top, bottom, shoulders, hem, cloth, fold) {
		for (let y = top; y <= bottom; y++) {
			const k = (y - top) / Math.max(1, bottom - top);
			const half = Math.round(lerp(shoulders, hem, Math.pow(k, 0.7)));
			for (let x = -half; x <= half; x++) {
				const crease = ((x - Math.floor(y / 4)) % fold + fold) % fold === 0 && Math.abs(x) < half - 1;
				layer.px(cx + x, y, x <= -half + 1 ? cloth[0] : crease || x >= half - 1 ? cloth[2] : cloth[1]);
			}
		}
	}

	// A standing saint in an icon's manner: halo, head, a long robe with a
	// gold stole, and a cross held before the breast.
	function saint(layer, cx, top, cloth, glow) {
		oval(layer, cx, top + 5, 6.4, 6.4, (dx, dy) => (dx * dx + dy * dy > 0.72 ? LEAF[4] : mixColor(LEAF[2], LEAF[3], glow)));
		robe(layer, cx, top + 10, top + 46, 5, 8, cloth, 5);
		for (let y = top + 12; y <= top + 46; y++) layer.px(cx, y, y % 6 === 0 ? LEAF[4] : LEAF[2]);
		oval(layer, cx, top + 5, 2.6, 3.4, (dx) => (dx > 0.35 ? FLESH[2] : dx < -0.4 ? FLESH[0] : FLESH[1]));
		for (let x = -3; x <= 3; x++) layer.px(cx + x, top + 2 + (Math.abs(x) === 3 ? 2 : Math.abs(x) === 2 ? 1 : 0), HAIR[0]);
		layer.px(cx - 3, top + 5, HAIR[0]);
		layer.px(cx + 3, top + 5, HAIR[1]);
		layer.px(cx - 1, top + 5, HAIR[1]);
		layer.px(cx + 1, top + 5, HAIR[1]);
		layer.px(cx, top + 8, HAIR[0]);
		// The hand and its cross.
		layer.px(cx - 3, top + 19, FLESH[0]);
		layer.px(cx - 3, top + 20, FLESH[1]);
		for (let y = top + 12; y <= top + 19; y++) layer.px(cx - 3, y, LEAF[4]);
		layer.px(cx - 4, top + 14, LEAF[4]);
		layer.px(cx - 2, top + 14, LEAF[4]);
	}

	define({
		name: 'backdrop_icon',
		kind: 'backdrop',
		pack: 'icon',
		title: 'Backdrop (Icon)',
		note: 'The background of the Icon pack, one seamless six-second loop: a dithered dusk, a nimbus of gold rays turning behind two breathing rings that halo a blessing figure, two standing saints beside it, small crosses twinkling, incense drifting up, and a skyline of onion domes with candle-lit windows.',
		w: NIGHT.w, h: NIGHT.h, fps: NIGHT.fps, frames: NIGHT.loop * NIGHT.fps, loopFrom: 0, anchor: 'center', seed: 733,
		phases: [{ name: 'the nimbus turns one ray', at: 0 }, { name: 'back to the start', at: 5 }],
		setup(sim) {
			sim.layer('sky', { kind: 'color' });
			sim.layer('nimbus', { kind: 'color' });
			sim.layer('crosses', { kind: 'color' });
			sim.layer('saints', { kind: 'color' });
			sim.layer('incense', { kind: 'color' });
			sim.layer('skyline', { kind: 'color' });
			const r = makeRng(1054);
			const S = sim.state;
			S.crosses = [];
			for (let i = 0; i < 46; i++) S.crosses.push({ x: r.int(2, NIGHT.w - 3), y: r.int(2, 66), times: r.int(1, 3), phase: r.angle(), big: r() < 0.3 });
			S.motes = [];
			for (let i = 0; i < 34; i++) S.motes.push({ x: r.int(4, NIGHT.w - 5), start: r.range(0, 1), rises: r.int(1, 2), sway: r.range(2, 7), turns: r.int(1, 3), phase: r.angle() });
			// Churches along the bottom: a tower, an onion dome, a cross.
			S.churches = [];
			let x = -4;
			while (x < NIGHT.w) {
				const radius = r.int(5, 11);
				const church = { x: x + radius + r.int(0, 3), radius, tower: r.int(4, 16), tint: r.pick(DOME_TINTS), lights: [] };
				for (let row = 0; row * 7 + 4 < church.tower; row++) {
					if (r() < 0.6) church.lights.push({ row, side: r.pick([-1, 0, 1]), times: r.int(1, 3), phase: r.angle() });
				}
				S.churches.push(church);
				x = church.x + radius + r.int(1, 6);
			}
		},
		update() {},
		draw(sim, t) {
			const L = sim.byName, S = sim.state;
			const p = ((t / NIGHT.loop) % 1 + 1) % 1;
			const w = NIGHT.w, h = NIGHT.h;
			const dither = (x, y) => BAYER4[(y & 3) * 4 + (x & 3)];
			// Dusk: dithered bands, darkest on top, an ember glow at the skyline.
			for (let y = 0; y < h; y++) {
				for (let x = 0; x < w; x++) {
					const band = Math.pow(y / h, 1.5) * (DUSK.length - 1) + (dither(x, y) - 0.5);
					L.sky.px(x, y, DUSK[Math.max(0, Math.min(DUSK.length - 1, Math.round(band)))]);
				}
			}
			// The nimbus: rays turning by one ray over the loop, two rings breathing.
			const cx = w / 2 - 0.5, cy = 34;
			const breath = 0.5 + 0.5 * Math.sin(p * TAU);
			for (let y = 0; y < 84; y++) {
				for (let x = 0; x < w; x++) {
					const dx = x - cx, dy = (y - cy) * 1.05;
					const reach = Math.hypot(dx, dy);
					if (reach < 13) continue;
					const ring = Math.abs(reach - 17) < 1.3 || Math.abs(reach - 22.5) < 0.6;
					if (ring) {
						L.nimbus.px(x, y, LEAF[2 + Math.round(breath * 2 + (dx + dy < 0 ? 1 : 0))], 0.55 + 0.25 * breath);
						continue;
					}
					if (reach < 26 || reach > 96) continue;
					const turn = ((Math.atan2(dy, dx) / TAU * RAYS + p) % 1 + 1) % 1;
					if (turn > 0.42) continue;
					// Each ray thins out and dims with distance.
					const power = (1 - (reach - 26) / 70) * (1 - Math.abs(turn - 0.21) / 0.21 * 0.5);
					if (power * 0.62 > dither(x, y)) L.nimbus.px(x, y, LEAF[power > 0.75 ? 2 : 1], 0.3 + 0.3 * power);
				}
			}
			for (const cross of S.crosses) {
				const glow = 0.5 + 0.5 * Math.sin(p * TAU * cross.times + cross.phase);
				if (glow < 0.25) continue;
				L.crosses.px(cross.x, cross.y, glow > 0.75 ? LEAF[5] : LEAF[3], 0.3 + 0.6 * glow);
				if (cross.big && glow > 0.6) {
					for (const [ox, oy] of [[1, 0], [-1, 0], [0, -1], [0, 1], [0, 2]]) L.crosses.px(cross.x + ox, cross.y + oy, LEAF[3], 0.5 * glow);
				}
			}
			// The figures. In the middle, inside the nimbus's rings (they are
			// the halo), a bearded figure in the manner of an icon: one hand
			// raised in blessing, the other holding a jewelled book. Beside
			// it, lower, two standing saints.
			const mx = Math.round(cx), my = cy;
			oval(L.saints, cx, cy, 15.6, 15.6 / 1.05, (dx, dy) => mixColor(LEAF[1], LEAF[2], 0.35 + 0.3 * breath - 0.3 * (dx * dx + dy * dy)));
			// Mantle and tunic: the mantle falls over the shoulder on the right.
			robe(L.saints, mx, my + 12, 88, 11, 30, ROBES.red, 6);
			for (let y = my + 12; y <= 88; y++) {
				const k = (y - my - 12) / (88 - my - 12);
				const half = Math.round(lerp(11, 30, Math.pow(k, 0.7)));
				for (let x = Math.round(lerp(2, -8, k)); x <= half; x++) {
					const crease = ((x + Math.floor(y / 3)) % 6 + 6) % 6 === 0 && x < half - 1;
					L.saints.px(mx + x, y, x >= half - 1 || crease ? ROBES.blue[2] : x <= Math.round(lerp(2, -8, k)) + 1 ? ROBES.blue[0] : ROBES.blue[1]);
				}
			}
			// The neck's gold band.
			for (let x = -5; x <= 5; x++) L.saints.px(mx + x, my + 11 + (Math.abs(x) > 3 ? -1 : 0), x % 2 === 0 ? LEAF[4] : LEAF[2]);
			// Hair to the shoulders, the face, the beard.
			oval(L.saints, cx, cy + 1, 8.2, 10.5, (dx) => (dx > 0.2 ? HAIR[1] : HAIR[0]));
			oval(L.saints, cx, cy + 0.5, 5.2, 7.2, (dx, dy) => (dx > 0.45 ? FLESH[2] : dx < -0.35 && dy < 0.3 ? FLESH[0] : FLESH[1]));
			for (let y = 4; y <= 9; y++) {
				const half = y < 7 ? 4 : 9 - y + 1;
				for (let x = -half; x <= half; x++) if (y > 5 || Math.abs(x) >= 2) L.saints.px(mx + x, my + y, x > 1 ? HAIR[1] : HAIR[0]);
			}
			for (const [x, y, c] of [[-3, -2, HAIR[1]], [-2, -2, HAIR[1]], [2, -2, HAIR[1]], [3, -2, HAIR[1]], [-2, -1, HAIR[1]], [2, -1, HAIR[1]],
				[0, -1, FLESH[2]], [0, 0, FLESH[2]], [0, 1, FLESH[2]], [0, 2, FLESH[2]], [-1, 3, FLESH[2]], [1, 3, FLESH[2]], [-1, 5, ROBES.red[1]], [0, 5, ROBES.red[1]], [1, 5, ROBES.red[1]],
				[-4, -4, HAIR[0]], [-3, -5, HAIR[0]], [3, -5, HAIR[0]], [4, -4, HAIR[1]], [0, -6, HAIR[0]], [-1, -6, HAIR[0]], [1, -6, HAIR[1]]]) L.saints.px(mx + x, my + y, c);
			// The blessing hand, and the book with its cover of gold and gems.
			for (const [x, y, c] of [[-13, 27, FLESH[0]], [-12, 27, FLESH[1]], [-13, 28, FLESH[0]], [-12, 28, FLESH[1]], [-11, 28, FLESH[2]], [-13, 29, FLESH[1]], [-12, 29, FLESH[1]], [-11, 29, FLESH[2]],
				[-13, 24, FLESH[0]], [-13, 25, FLESH[0]], [-13, 26, FLESH[0]], [-12, 25, FLESH[1]], [-12, 26, FLESH[1]], [-11, 27, FLESH[2]], [-13, 30, ROBES.red[0]], [-12, 30, ROBES.red[0]]]) L.saints.px(mx + x, my + y, c);
			for (let y = 24; y <= 38; y++) {
				for (let x = 5; x <= 15; x++) {
					const rim = y === 24 || y === 38 || x === 5 || x === 15;
					const gem = (x === 10 && (y === 27 || y === 31 || y === 35)) || (y === 31 && (x === 7 || x === 13));
					L.saints.px(mx + x, my + y, rim ? LEAF[1] : gem ? (y === 31 && x === 10 ? ROBES.red[0] : ROBES.blue[0]) : (x + y) % 5 === 0 ? LEAF[4] : LEAF[3]);
				}
			}
			L.saints.px(mx + 4, my + 33, FLESH[1]);
			L.saints.px(mx + 4, my + 34, FLESH[1]);
			L.saints.px(mx + 5, my + 34, FLESH[2]);
			saint(L.saints, 34, 34, ROBES.green, breath);
			saint(L.saints, w - 35, 34, ROBES.red, breath);
			// Incense: motes swaying upward, fading in and out along the way.
			for (const mote of S.motes) {
				const along = ((mote.start + p * mote.rises) % 1 + 1) % 1;
				const y = Math.round((1 - along) * (h - 14));
				const x = Math.round(mote.x + Math.sin(p * TAU * mote.turns + mote.phase) * mote.sway);
				L.incense.px(x, y, LEAF[4], 0.55 * Math.sin(along * Math.PI));
			}
			// The skyline.
			for (const church of S.churches) {
				const base = h - church.tower;
				const half = Math.max(2, Math.round(church.radius * 0.62));
				for (let y = base; y < h; y++) {
					for (let x = church.x - half; x <= church.x + half; x++) L.skyline.px(x, y, x === church.x - half ? WALL[2] : x === church.x + half ? WALL[0] : WALL[1]);
				}
				for (const light of church.lights) {
					const on = Math.sin(p * TAU * light.times + light.phase);
					if (on < -0.3) continue;
					const lamp = on > 0.4 ? LEAF[4] : LEAF[2];
					const lx = church.x + light.side * Math.max(1, half - 2), ly = base + 3 + light.row * 7;
					L.skyline.px(lx, ly, lamp, 0.9);
					L.skyline.px(lx, ly + 1, lamp, 0.9);
					L.skyline.px(lx, ly + 2, LEAF[1], 0.9);
				}
				// The dome: narrow at the drum, swelling, drawn to a point.
				const tall = Math.round(church.radius * 1.9);
				for (let j = 0; j < tall; j++) {
					const k = j / (tall - 1);
					const width = Math.round(church.radius * Math.pow(Math.sin(Math.PI * (0.18 + 0.82 * k)), 0.85));
					for (let x = -width; x <= width; x++) {
						// Lit from the upper left, dark toward the right rim.
						const side = width === 0 ? 0 : x / width;
						const tone = side < -0.45 ? 0.2 : side > 0.55 ? 0.72 : side > 0.1 ? 0.52 : 0.36;
						L.skyline.px(church.x + x, base - 1 - j, mixColor(church.tint, BLACK, tone + 0.1 * (1 - k)));
					}
					if (j % 4 === 1 && width > 2) L.skyline.px(church.x - Math.round(width * 0.5), base - 1 - j, mixColor(church.tint, WHITE, 0.35));
				}
				// The cross: a short bar, the long bar, a slanted foot.
				const tip = base - tall - 1;
				for (let j = 0; j < 9; j++) L.skyline.px(church.x, tip - j, LEAF[3]);
				L.skyline.px(church.x - 1, tip - 7, LEAF[3]);
				L.skyline.px(church.x + 1, tip - 7, LEAF[3]);
				for (let x = -2; x <= 2; x++) L.skyline.px(church.x + x, tip - 5, LEAF[4]);
				L.skyline.px(church.x - 1, tip - 3, LEAF[3]);
				L.skyline.px(church.x + 1, tip - 2, LEAF[3]);
			}
		},
	});

	// ---------------------------------------------------------------- title
	// The game's title, built out of falling blocks and then kept alive. Unlike
	// the board effects it does not end: an intro plays once (blocks rain down
	// and lock into the five characters, each finished character flashes, a
	// beam sweeps the line and leaves an underline), then the frames from
	// `loopFrom` on repeat for ever - a shine crossing the letters, the
	// characters bobbing like a wave, sparkles, embers, small tetrominoes
	// falling behind. Everything in the loop is a function of the loop's phase
	// and nothing is alive where it wraps, so it goes round without a seam.
	const GLYPHS = FX.titleGlyphs || require('./title_glyphs.js');
	const TITLE = { w: 224, h: 60, block: 3, x0: 22, y0: 9, intro: 2.2, loop: 3.0, fall: 0.26, drop: 70, sweep: [1.45, 1.8] };
	const TITLE_COLORS = hexes(['#33d9f2', '#f2cc40', '#bf66f2', '#66e680', '#f27373']);
	// Every lit pixel of the title: where its block ends up and when it lands.
	function titleBlocks() {
		const blocks = [];
		const done = [];
		GLYPHS.glyphs.forEach((rows, c) => {
			let last = 0;
			rows.forEach((line, row) => {
				for (let col = 0; col < line.length; col++) {
					if (line[col] !== '#') continue;
					// Bottom rows first, each column a touch out of step.
					const delay = 0.14 * c + (GLYPHS.size - 1 - row) * 0.04 + FX.noise3(col * 7.3, row * 3.1, c * 5.7) * 0.06;
					const land = delay + TITLE.fall;
					last = Math.max(last, land);
					blocks.push({ c, col, row, x: TITLE.x0 + (c * GLYPHS.size + col) * TITLE.block, y: TITLE.y0 + row * TITLE.block, delay, land,
						foot: row === GLYPHS.size - 1 || rows[row + 1][col] !== '#' });
				}
			});
			done.push(last);
		});
		return { blocks, done };
	}

	define({
		name: 'title',
		kind: 'title',
		title: 'Title',
		note: 'The title screen: blocks rain down and lock into the five characters, each finished character flashes with a ring, a plasma beam sweeps the line and leaves a glowing underline - then it idles for ever: a shine crosses the letters, they bob like a wave, sparkles and embers come and go, small tetrominoes fall behind. The loop starts where the timeline is marked.',
		w: TITLE.w, h: TITLE.h, frames: Math.round((TITLE.intro + TITLE.loop) * 30), loopFrom: Math.round(TITLE.intro * 30), anchor: 'center', seed: 131,
		phases: [{ name: 'rain', at: 0 }, { name: 'lock', at: 0.55 }, { name: 'sweep', at: TITLE.sweep[0] }, { name: 'settle', at: TITLE.sweep[1] },
			{ name: 'idle: shine', at: TITLE.intro }, { name: 'idle: sparkle', at: TITLE.intro + TITLE.loop * 0.45 }],
		setup(sim) {
			sim.layer('rain', { kind: 'color' });
			sim.layer('dust', { ramp: 'dust', erode: { amount: 0.35, scale: 0.25, speed: 3 } });
			sim.layer('underline', { ramp: 'gold' });
			sim.layer('letters', { kind: 'color', outline: '#060a18e6' });
			sim.layer('ring', { ramp: 'white' });
			sim.layer('beam', { ramp: 'plasma', outline: '#061040c0', erode: { amount: 0.3, scale: 0.22, speed: 5 } });
			sim.layer('sparks', { ramp: 'gold' });
			sim.layer('stars', { kind: 'color' });
			sim.layer('flash', { ramp: 'white' });
			Object.assign(sim.state, titleBlocks());
		},
		// Phase of the idle loop, continuous through the end of the intro.
		phaseOf(t) {
			return ((((t - TITLE.intro) / TITLE.loop) % 1) + 1) % 1;
		},
		// The vertical bob of character `c`: a wave running along the title.
		bob(t, c) {
			const strength = clamp01((t - (TITLE.intro - 0.3)) / 0.3);
			return Math.round(Math.sin((this.phaseOf(t) - c * 0.13) * TAU) * 1.3 * strength);
		},
		update(sim, t) {
			const L = sim.byName, r = sim.rng, S = sim.state;
			const half = TITLE.block / 2;
			for (const b of S.blocks) {
				if (b.fired || t < b.land) continue;
				b.fired = true;
				// A block lands: now and then a spark, and dust under the feet.
				if (r() < 0.22) sparks(sim, L.sparks, b.x + half, b.y, 1, { angle: [-2.6, -0.5], speed: [30, 80], gravity: 260, life: [0.12, 0.25] });
				if (b.foot && r() < 0.5) {
					puffs(sim, L.dust, 1, (i, rr) => ({ x: b.x + half, y: b.y + TITLE.block, vx: rr.range(-30, 30), vy: -rr.range(4, 16), drag: 5, life: rr.range(0.2, 0.32), size: [1.2, rr.range(2.5, 4)], heat: [0.9, 0.2] }));
				}
			}
			S.done.forEach((time, c) => {
				if (!sim.once('done' + c, time)) return;
				const cx = TITLE.x0 + (c + 0.5) * GLYPHS.size * TITLE.block - 1.5, cy = TITLE.y0 + 7.5 * TITLE.block;
				sparks(sim, L.sparks, cx, cy, 12, { speed: [40, 120], life: [0.15, 0.35], spread: 10, spreadY: 8 });
				stars(sim, L.stars, 3, [cx - 16, cy - 16, cx + 16, cy + 12], { delay: 0.12, colors: [TITLE_COLORS[c], WHITE] });
			});
			if (sim.during(TITLE.sweep[0], TITLE.sweep[1])) {
				const head = lerp(6, TITLE.w - 6, ease.inOut(sim.k(TITLE.sweep[0], TITLE.sweep[1])));
				sparks(sim, L.sparks, head, 30, 2, { angle: [Math.PI * 0.5, Math.PI * 1.5], speed: [20, 110], life: [0.12, 0.3], spreadY: 12 });
			}
			if (sim.once('settle', TITLE.sweep[1])) stars(sim, L.stars, 9, [16, 8, TITLE.w - 16, 50], { delay: 0.18, colors: GOLDS });
			if (t < TITLE.intro) return;
			// The idle loop. Whatever is born here is gone before it wraps.
			const p = this.phaseOf(t);
			if (p > 0.08 && p < 0.42 && sim.ticks % 2 === 0) {
				const band = lerp(-30, TITLE.w + 30, (p - 0.08) / 0.34);
				const lit = S.blocks.filter((b) => Math.abs(b.x + (b.y - 30) * 0.8 - band) < 6);
				if (lit.length) {
					const b = r.pick(lit);
					sim.emit({ layer: L.stars, shape: 'star', x: b.x + 1, y: b.y + 1 + this.bob(t, b.c), life: r.range(0.14, 0.24), color: WHITE, size: (k) => 2 * ease.bell(k) });
				}
			}
			if (p > 0.45 && p < 0.85) {
				if (sim.ticks % 5 === 0) embers(sim, L.sparks, 1, [TITLE.x0, 44, TITLE.x0 + 180, 50], { life: [0.3, 0.42] });
				if (sim.ticks % 12 === 0) stars(sim, L.stars, 1, [14, 6, TITLE.w - 14, 46], { delay: 0.02, colors: GOLDS.concat(TITLE_COLORS) });
			}
		},
		draw(sim, t) {
			const L = sim.byName, S = sim.state;
			const p = this.phaseOf(t);
			const size = TITLE.block;
			// Behind everything: small tetrominoes falling, one loop = whole falls.
			const veil = 0.42 * clamp01((t - 0.9) / 1.0);
			if (veil > 0) {
				for (let i = 0; i < 9; i++) {
					const shape = MINOS[i % 7], color = PIECES[i % 7];
					const x = 8 + ((i * 53) % (TITLE.w - 20));
					const y = ((i * 23 + p * (TITLE.h + 16) * (1 + (i % 2))) % (TITLE.h + 16)) - 8;
					for (const [cx, cy] of shape) for (let d = 0; d < 4; d++) L.rain.px(x + cx * 2 + (d & 1), y + cy * 2 + (d >> 1), color, veil);
				}
			}
			// The underline the beam leaves, breathing with the loop.
			const drawn = sim.k(TITLE.sweep[0] + 0.05, TITLE.sweep[1] + 0.05);
			if (drawn > 0) {
				const glow = t < TITLE.intro ? 0.72 : 0.72 + 0.2 * Math.sin(p * TAU);
				L.underline.beam(TITLE.x0 - 8, lerp(TITLE.x0 - 8, TITLE.x0 + 188, ease.inOut(drawn)), 50, 1.6, glow);
			}
			// The letters.
			const sweeping = sim.during(TITLE.sweep[0], TITLE.sweep[1] + 0.1);
			const head = lerp(6, TITLE.w - 6, ease.inOut(sim.k(TITLE.sweep[0], TITLE.sweep[1])));
			const shining = t >= TITLE.intro && p > 0.08 && p < 0.42;
			const band = lerp(-30, TITLE.w + 30, (p - 0.08) / 0.34);
			for (const b of S.blocks) {
				if (t < b.delay) continue;
				let y = b.y;
				const u = (t - b.delay) / TITLE.fall;
				if (u < 1) {
					y = b.y - TITLE.drop * (1 - u * u);
				} else {
					const since = t - b.land;
					if (since < 0.25) y = b.y - Math.round(2.4 * Math.abs(Math.sin(since * 38)) * Math.exp(-since * 15));
					y += this.bob(t, b.c);
				}
				let white = 0;
				if (u >= 1 && t - b.land < 0.07) white = 1;
				const since = t - S.done[b.c];
				if (since >= 0 && since < 0.2) white = Math.max(white, 1 - since / 0.2);
				if (sweeping) white = Math.max(white, 1 - Math.abs(b.x - head) / 14);
				if (shining) {
					const off = Math.abs(b.x + (b.y - 30) * 0.8 - band);
					white = Math.max(white, off < 5 ? 0.8 : off < 9 ? 0.35 : 0);
				}
				const base = mixColor(TITLE_COLORS[b.c], WHITE, clamp01(white));
				const light = mixColor(base, WHITE, 0.5), dark = mixColor(base, BLACK, 0.38);
				for (let j = 0; j < size; j++) {
					for (let i = 0; i < size; i++) {
						L.letters.px(b.x + i, y + j, j === 0 || (i === 0 && j < size - 1) ? light : j === size - 1 || i === size - 1 ? dark : base);
					}
				}
			}
			// A ring off every finished character.
			S.done.forEach((time, c) => {
				const k = (t - time) / 0.36;
				if (k < 0 || k >= 1) return;
				L.ring.ring(TITLE.x0 + (c + 0.5) * GLYPHS.size * size - 1.5, TITLE.y0 + 7.5 * size, lerp(5, 24, ease.outCubic(k)), lerp(4, 1.2, k), 1 - k);
			});
			// The sweep: a beam with a hot head.
			if (sim.during(TITLE.sweep[0], TITLE.sweep[1])) {
				const k = sim.k(TITLE.sweep[0], TITLE.sweep[1]);
				L.beam.beam(head - 60, head + 4, 30.5, 2 + 9 * ease.bell(k), 1);
				L.flash.disc(head, 30, 6, 1, 0.5);
			}
		},
	});

	// -------------------------------------------------------------- icon fx
	// The effects of the "Icon FX" pack: every board effect above, with the
	// signs of an icon laid over it - a three-barred cross, a nimbus of rings,
	// rays of gold - on the same timeline. (The exporter gives the whole of it
	// the pack's colors: export.js --pack iconfx.)
	// A three-barred cross of light; `s` is its unit (it stands 9 s tall).
	function crossSign(layer, cx, cy, s, v) {
		if (v <= 0) return;
		const thick = s >= 3 ? [-0.5, 0.5] : [0];
		for (const o of thick) {
			layer.line(cx + o, cy - 4 * s, cx + o, cy + 5 * s, v);
			layer.line(cx - 1.2 * s, cy - 2.8 * s + o, cx + 1.2 * s, cy - 2.8 * s + o, v);
			layer.line(cx - 2.6 * s, cy - 1.2 * s + o, cx + 2.6 * s, cy - 1.2 * s + o, v);
			layer.line(cx - 1.5 * s, cy + 2.2 * s + o, cx + 1.5 * s, cy + 3.4 * s + o, v);
		}
	}
	// Rays from a ring outward, cooling toward their tips.
	function raySigns(layer, cx, cy, from, to, count, turn, v) {
		if (v <= 0 || to <= from) return;
		for (let i = 0; i < count; i++) {
			const a = turn + (i * TAU) / count;
			layer.line(cx + Math.cos(a) * from, cy + Math.sin(a) * from, cx + Math.cos(a) * to, cy + Math.sin(a) * to, v, 0.15 * v);
		}
	}
	const ICON_SIGNS = {
		lock(sim, t, L) {
			crossSign(L.sign, 20, 20, 1.5, 1 - sim.k(0, 0.2));
		},
		hard_drop(sim, t, L) {
			const k = sim.k(0, 0.36);
			if (k >= 1) return;
			L.nimbus.ring(56, 44, lerp(6, 44, ease.outCubic(k)), 1.6, 1 - k, 0.3);
			crossSign(L.sign, 56, 28 - 10 * k, 1.3, 1 - k);
		},
		garbage(sim, t, L) {
			const k = sim.k(0, 0.36);
			if (k < 1) L.nimbus.ring(64, 40, lerp(10, 58, ease.outCubic(k)), 1.4, 0.8 * (1 - k), 0.25);
		},
		line_clear(sim, t, L) {
			// Small crosses light up along the row, one after another.
			for (let i = 0; i < 6; i++) {
				const k = (t - 0.06 - i * 0.04) / 0.28;
				if (k > 0 && k < 1) crossSign(L.sign, 22 + i * 20, 20, 1.3, ease.bell(k));
			}
		},
		tetris(sim, t, L) {
			if (t < 0.2) return;
			const k = sim.k(0.2, 0.9);
			if (k >= 1) return;
			const light = Math.pow(1 - k, 0.7);
			L.nimbus.ring(88, 64, 30, 1.8, light);
			L.nimbus.ring(88, 64, 36, 0.9, light * 0.8);
			raySigns(L.nimbus, 88, 64, 40, 40 + 46 * ease.outCubic(k), 16, k * 0.4, light);
			crossSign(L.sign, 88, 62, 5, 1 - ease.in(k));
		},
		tspin(sim, t, L) {
			if (t < 0.25) return;
			const k = sim.k(0.25, 0.7);
			if (k >= 1) return;
			L.nimbus.ring(48, 48, 24, 1.5, 1 - k);
			for (let i = 0; i < 8; i++) {
				const a = k * Math.PI + (i * TAU) / 8;
				L.nimbus.disc(48 + Math.cos(a) * 24, 48 + Math.sin(a) * 24, 1.8, 1 - k, 0.3);
			}
			crossSign(L.sign, 48, 47, 2.2, 1 - k);
		},
		perfect_clear(sim, t, L) {
			if (t < 0.3) return;
			const k = sim.k(0.3, 1.25);
			if (k >= 1) return;
			const light = ease.bell(Math.pow(k, 0.6));
			L.nimbus.ring(80, 106, 46, 2, light);
			L.nimbus.ring(80, 106, 54, 1, light * 0.8);
			raySigns(L.nimbus, 80, 106, 60, 60 + 50 * ease.outCubic(k), 24, -k * 0.3, light);
			crossSign(L.sign, 80, 104, 9, light);
		},
		ko(sim, t, L) {
			if (t < 0.2) return;
			const k = sim.k(0.2, 1.3);
			if (k >= 1) return;
			// The nimbus closes in and goes out.
			L.nimbus.ring(88, 112, lerp(52, 22, ease.inOut(k)), 1.6, 0.9 * (1 - k));
			crossSign(L.sign, 88, 110, 8, 0.9 * (1 - ease.in(k)));
		},
	};
	for (const base of defs.filter((def) => !def.kind)) {
		define(Object.assign({}, base, {
			name: 'icon_' + base.name,
			event: base.name,
			pack: 'iconfx',
			title: base.title + ' (Icon)',
			note: base.note + ' Icon FX: with a cross, a nimbus or rays of gold laid over it.',
			setup(sim) {
				base.setup(sim);
				sim.layer('nimbus', { ramp: 'gold' });
				sim.layer('sign', { ramp: 'gold', outline: '#2a0806c0' });
			},
			draw(sim, t) {
				base.draw(sim, t);
				ICON_SIGNS[base.name](sim, t, sim.byName);
			},
		}));
	}

	for (const def of defs) {
		def.fps = def.fps || 30;
		def.scale = 2;
		FX.effects[def.name] = def;
	}
	FX.effectList = defs;
	if (typeof module !== 'undefined' && module.exports) module.exports = FX;
})(typeof globalThis !== 'undefined' ? globalThis : this);
