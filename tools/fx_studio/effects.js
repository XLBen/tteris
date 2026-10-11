// The effects of the "Pixel FX" resource pack, one per game event.
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

	for (const def of defs) {
		def.fps = 30;
		def.scale = 2;
		FX.effects[def.name] = def;
	}
	FX.effectList = defs;
	if (typeof module !== 'undefined' && module.exports) module.exports = FX;
})(typeof globalThis !== 'undefined' ? globalThis : this);
