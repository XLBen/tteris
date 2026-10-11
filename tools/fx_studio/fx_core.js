// PixelFX core: a small deterministic engine for pixel-art effect animations.
//
// An effect is a timeline of phases played by a Sim: emitters give birth to
// particles, particles age along their curves, bounce, leave trails, spawn
// children when they die; scalar "heat" layers are quantized through a color
// ramp with ordered dithering (that is what makes the result read as pixel
// art instead of as a blurry gradient), eroded by animated noise and outlined;
// a cellular fire field carries flames upward. The Sim renders straight-alpha
// RGBA frames at the art resolution - nothing here needs a canvas, so the same
// file runs in the browser (index.html draws the frames with Canvas 2D) and in
// Node (export.js writes them as sprite sheets for the game's resource pack).
(function (root) {
	'use strict';

	const TICK = 1 / 60;
	const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map((v) => (v + 0.5) / 16);

	// ---------------------------------------------------------------- random
	function makeRng(seed) {
		let a = seed >>> 0;
		const f = () => {
			a = (a + 0x6d2b79f5) >>> 0;
			let t = a;
			t = Math.imul(t ^ (t >>> 15), t | 1);
			t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
			return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
		};
		f.range = (lo, hi) => lo + (hi - lo) * f();
		f.int = (lo, hi) => Math.floor(f.range(lo, hi + 1));
		f.sign = () => (f() < 0.5 ? -1 : 1);
		f.pick = (list) => list[Math.floor(f() * list.length)];
		f.angle = () => f() * Math.PI * 2;
		return f;
	}

	function hash3(x, y, z) {
		let h = Math.imul(x, 374761393) ^ Math.imul(y, 668265263) ^ Math.imul(z, 1274126177);
		h = Math.imul(h ^ (h >>> 13), 1103515245);
		return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
	}

	// Smooth value noise, 0..1.
	function noise3(x, y, z) {
		const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
		let xf = x - xi, yf = y - yi, zf = z - zi;
		xf = xf * xf * (3 - 2 * xf);
		yf = yf * yf * (3 - 2 * yf);
		zf = zf * zf * (3 - 2 * zf);
		const lerp = (a, b, t) => a + (b - a) * t;
		const plane = (zz) => lerp(
			lerp(hash3(xi, yi, zz), hash3(xi + 1, yi, zz), xf),
			lerp(hash3(xi, yi + 1, zz), hash3(xi + 1, yi + 1, zz), xf), yf);
		return lerp(plane(zi), plane(zi + 1), zf);
	}

	function fbm(x, y, z) {
		return noise3(x, y, z) * 0.65 + noise3(x * 2.1 + 9.2, y * 2.1 - 4.7, z * 1.7) * 0.35;
	}

	// ---------------------------------------------------------------- curves
	const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
	const lerp = (a, b, t) => a + (b - a) * t;
	const ease = {
		linear: (k) => k,
		in: (k) => k * k,
		out: (k) => 1 - (1 - k) * (1 - k),
		outCubic: (k) => 1 - Math.pow(1 - k, 3),
		outExpo: (k) => (k >= 1 ? 1 : 1 - Math.pow(2, -10 * k)),
		inOut: (k) => (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2),
		// 0 -> 1 -> 0: the shape of something that appears and goes.
		bell: (k) => Math.sin(Math.PI * clamp01(k)),
		// Fast up, slow down.
		pop: (k) => (k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8),
	};

	// A particle property: a number, [from, to] or a function of life 0..1.
	function curve(value, k) {
		if (typeof value === 'function') return value(k);
		if (Array.isArray(value)) return value[0] + (value[1] - value[0]) * k;
		return value;
	}

	// ---------------------------------------------------------------- colors
	function hex(text) {
		const s = text.replace('#', '');
		const n = (i) => parseInt(s.substr(i, 2), 16) / 255;
		return [n(0), n(2), n(4), s.length >= 8 ? n(6) : 1];
	}

	// Ramps run from the coolest visible step to the hottest.
	const RAMPS = {
		fire: ['#4a1010c8', '#8c1c14', '#c83418', '#f06820', '#f8a030', '#fcd860', '#fff8d0', '#ffffff'],
		plasma: ['#0c2470c8', '#1448b0', '#1c7cdc', '#30b8f4', '#78e4fc', '#c8f8ff', '#ffffff'],
		arcane: ['#280c58c8', '#501ca0', '#8430d8', '#b458f8', '#dc98fc', '#f4dcff', '#ffffff'],
		gold: ['#582c08c8', '#9c5410', '#d88818', '#f8bc28', '#fce070', '#fff8c8', '#ffffff'],
		smoke: ['#2a222870', '#3c3038a0', '#544650b8', '#6e5e66c8', '#8a7a80d0'],
		dust: ['#4a403860', '#6a5e5290', '#8c7e6eac', '#b0a290c0', '#d0c4b0cc'],
		white: ['#ffffff38', '#ffffff70', '#ffffffa8', '#ffffffd8', '#ffffff'],
		ember: ['#a82810', '#f06820', '#fcd860', '#ffffff'],
	};
	const rampCache = {};
	function ramp(name) {
		if (!rampCache[name]) rampCache[name] = RAMPS[name].map(hex);
		return rampCache[name];
	}

	// ---------------------------------------------------------------- layers
	// A scalar layer holds "heat" per pixel; a color layer holds RGBA pixels.
	class Layer {
		constructor(sim, name, options) {
			const o = options || {};
			this.sim = sim;
			this.name = name;
			this.w = sim.w;
			this.h = sim.h;
			this.kind = o.kind || 'scalar';
			this.ramp = this.kind === 'scalar' ? ramp(o.ramp || 'fire') : null;
			this.blend = o.blend || 'mix';
			this.dither = o.dither === undefined ? 1 : o.dither;
			this.persist = o.persist || 0; // 0 = cleared every frame, else the per-tick decay
			this.outline = o.outline ? hex(o.outline) : null;
			this.erode = o.erode || null; // {amount, scale, speed} - amount may be a function of time
			this.fire = o.fire || null; // {cooling, speed, row} - a cellular fire field
			this.fuel = this.fire ? new Float32Array(this.w) : null; // heat fed into its row
			this.visible = true;
			this.f = new Float32Array(this.w * this.h * (this.kind === 'scalar' ? 1 : 4));
		}

		clear() {
			this.f.fill(0);
		}

		plot(x, y, v) {
			x = Math.round(x);
			y = Math.round(y);
			if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
			const i = y * this.w + x;
			if (v > this.f[i]) this.f[i] = v;
		}

		// A filled disc; `soft` 0..1 is how much the heat falls toward the rim,
		// `sy` squashes it into an ellipse.
		disc(cx, cy, r, v, soft, sy) {
			soft = soft === undefined ? 0.6 : soft;
			sy = sy || 1;
			if (r < 0.75) {
				this.plot(cx, cy, v);
				return;
			}
			const ry = r * sy;
			const x0 = Math.max(0, Math.floor(cx - r)), x1 = Math.min(this.w - 1, Math.ceil(cx + r));
			const y0 = Math.max(0, Math.floor(cy - ry)), y1 = Math.min(this.h - 1, Math.ceil(cy + ry));
			for (let y = y0; y <= y1; y++) {
				for (let x = x0; x <= x1; x++) {
					const dx = (x - cx) / r, dy = (y - cy) / ry;
					const d = dx * dx + dy * dy;
					if (d > 1) continue;
					const value = v * (1 - soft * d);
					const i = y * this.w + x;
					if (value > this.f[i]) this.f[i] = value;
				}
			}
		}

		ring(cx, cy, r, thickness, v, sy) {
			sy = sy || 1;
			const outer = r + thickness / 2;
			const x0 = Math.max(0, Math.floor(cx - outer)), x1 = Math.min(this.w - 1, Math.ceil(cx + outer));
			const y0 = Math.max(0, Math.floor(cy - outer * sy)), y1 = Math.min(this.h - 1, Math.ceil(cy + outer * sy));
			for (let y = y0; y <= y1; y++) {
				for (let x = x0; x <= x1; x++) {
					const dx = x - cx, dy = (y - cy) / sy;
					const off = Math.abs(Math.sqrt(dx * dx + dy * dy) - r) / (thickness / 2);
					if (off > 1) continue;
					const value = v * (1 - off * off * 0.7);
					const i = y * this.w + x;
					if (value > this.f[i]) this.f[i] = value;
				}
			}
		}

		rect(x0, y0, x1, y1, v) {
			x0 = Math.max(0, Math.round(x0));
			y0 = Math.max(0, Math.round(y0));
			x1 = Math.min(this.w, Math.round(x1));
			y1 = Math.min(this.h, Math.round(y1));
			for (let y = y0; y < y1; y++) {
				for (let x = x0; x < x1; x++) {
					const i = y * this.w + x;
					if (v > this.f[i]) this.f[i] = v;
				}
			}
		}

		// A beam of light along x (or along y with `upright`): hottest on its
		// axis, cooler toward the edges, with pointed ends.
		beam(from, to, axis, half, v, upright) {
			if (half <= 0 || to <= from) return;
			const a0 = Math.max(0, Math.round(from)), a1 = Math.min(upright ? this.h : this.w, Math.round(to));
			const b0 = Math.max(0, Math.floor(axis - half)), b1 = Math.min((upright ? this.w : this.h) - 1, Math.ceil(axis + half));
			for (let b = b0; b <= b1; b++) {
				const off = Math.abs(b + 0.5 - axis) / half;
				if (off > 1) continue;
				for (let a = a0; a < a1; a++) {
					const tip = Math.min(a - from, to - 1 - a) / (half * 1.6);
					if (off > tip + 0.2) continue;
					const value = v * (1 - 0.5 * off * off);
					const i = upright ? a * this.w + b : b * this.w + a;
					if (value > this.f[i]) this.f[i] = value;
				}
			}
		}

		line(x0, y0, x1, y1, v, v1) {
			x0 = Math.round(x0); y0 = Math.round(y0); x1 = Math.round(x1); y1 = Math.round(y1);
			const dx = Math.abs(x1 - x0), dy = Math.abs(y1 - y0);
			const sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
			const steps = Math.max(dx, dy) || 1;
			let err = dx - dy, n = 0;
			for (;;) {
				this.plot(x0, y0, v1 === undefined ? v : lerp(v, v1, n / steps));
				if (x0 === x1 && y0 === y1) break;
				const e2 = 2 * err;
				if (e2 > -dy) { err -= dy; x0 += sx; }
				if (e2 < dx) { err += dx; y0 += sy; }
				n++;
			}
		}

		// Color layers only.
		px(x, y, color, alpha) {
			x = Math.round(x);
			y = Math.round(y);
			if (x < 0 || y < 0 || x >= this.w || y >= this.h) return;
			const i = (y * this.w + x) * 4;
			this.f[i] = color[0];
			this.f[i + 1] = color[1];
			this.f[i + 2] = color[2];
			this.f[i + 3] = alpha === undefined ? 1 : alpha;
		}

		// One tick of a persistent layer: the fire field climbs and cools, a
		// plain trail layer just fades.
		tick(rng) {
			if (this.fire) {
				const w = this.w, h = this.h, f = this.f, cooling = this.fire.cooling;
				const base = this.fire.row * w;
				for (let pass = 0; pass < (this.fire.speed || 1); pass++) {
					// The fuel row burns on every pass; flames climb from it.
					for (let x = 0; x < w; x++) f[base + x] = this.fuel[x];
					for (let y = 0; y < h - 1; y++) {
						for (let x = 0; x < w; x++) {
							const sx = Math.min(w - 1, Math.max(0, x + Math.floor(rng() * 3) - 1));
							const below = f[(y + 1) * w + sx];
							f[y * w + x] = below > 0 ? Math.max(0, below - rng() * cooling) : 0;
						}
					}
				}
			} else if (this.persist) {
				// Trails fade faster at the very end, so the timeline closes empty.
				const keep = this.sim.duration - this.sim.t < 0.12 ? this.persist * 0.6 : this.persist;
				for (let i = 0; i < this.f.length; i++) this.f[i] = this.f[i] < 0.03 ? 0 : this.f[i] * keep;
			}
		}

		// Writes this layer over the premultiplied accumulation buffer.
		composite(acc, time) {
			const w = this.w, h = this.h, f = this.f;
			if (this.kind === 'color') {
				for (let i = 0; i < w * h; i++) {
					const a = f[i * 4 + 3];
					if (a > 0) blendPixel(acc, i, f[i * 4], f[i * 4 + 1], f[i * 4 + 2], a, this.blend);
				}
				return;
			}
			const steps = this.ramp.length;
			const erode = this.erode;
			const amount = erode ? curve(erode.amount, time) : 0;
			const shown = this.outline ? new Uint8Array(w * h) : null;
			for (let y = 0; y < h; y++) {
				for (let x = 0; x < w; x++) {
					const i = y * w + x;
					let v = f[i];
					if (v <= 0) continue;
					if (amount > 0) v -= amount * fbm(x * erode.scale, y * erode.scale, time * erode.speed);
					if (v <= 0) continue;
					// Dithered from the bottom up: faint heat thins out to nothing
					// instead of lingering as a full lowest step.
					if (v < 0.02) continue;
					const level = Math.floor(Math.min(v, 0.999) * steps + (BAYER[(y & 3) * 4 + (x & 3)] - 1) * this.dither);
					if (level < 0) continue;
					const c = this.ramp[Math.min(steps - 1, level)];
					blendPixel(acc, i, c[0], c[1], c[2], c[3], this.blend);
					if (shown) shown[i] = 1;
				}
			}
			if (!shown) return;
			const o = this.outline;
			for (let y = 0; y < h; y++) {
				for (let x = 0; x < w; x++) {
					const i = y * w + x;
					if (shown[i]) continue;
					if ((x > 0 && shown[i - 1]) || (x < w - 1 && shown[i + 1]) || (y > 0 && shown[i - w]) || (y < h - 1 && shown[i + w])) {
						blendUnder(acc, i, o[0], o[1], o[2], o[3]);
					}
				}
			}
		}
	}

	function blendPixel(acc, i, r, g, b, a, mode) {
		const j = i * 4;
		if (mode === 'add') {
			acc[j] += r * a;
			acc[j + 1] += g * a;
			acc[j + 2] += b * a;
			acc[j + 3] = Math.max(acc[j + 3], a);
		} else {
			const keep = 1 - a;
			acc[j] = r * a + acc[j] * keep;
			acc[j + 1] = g * a + acc[j + 1] * keep;
			acc[j + 2] = b * a + acc[j + 2] * keep;
			acc[j + 3] = a + acc[j + 3] * keep;
		}
	}

	// An outline goes behind whatever is already there.
	function blendUnder(acc, i, r, g, b, a) {
		const j = i * 4;
		const room = (1 - acc[j + 3]) * a;
		acc[j] += r * room;
		acc[j + 1] += g * room;
		acc[j + 2] += b * room;
		acc[j + 3] += room;
	}

	// ------------------------------------------------------------------- sim
	class Sim {
		constructor(def, seed) {
			this.def = def;
			this.w = def.w;
			this.h = def.h;
			this.fps = def.fps || 30;
			this.frames = def.frames;
			this.duration = def.frames / this.fps;
			this.rng = makeRng(seed === undefined ? def.seed || 1 : seed);
			this.t = 0;
			this.ticks = 0;
			this.layers = [];
			this.byName = {};
			this.parts = [];
			this.fired = {};
			this.state = {};
			this.stats = { born: 0, died: 0, alive: 0, peak: 0 };
			this.acc = new Float32Array(this.w * this.h * 4);
			def.setup(this);
		}

		layer(name, options) {
			const made = new Layer(this, name, options);
			this.layers.push(made);
			this.byName[name] = made;
			return made;
		}

		// True exactly once, on the first tick at or after `time`.
		once(key, time) {
			if (this.fired[key] || this.t < time) return false;
			this.fired[key] = true;
			return true;
		}

		// True on every tick inside [from, to).
		during(from, to) {
			return this.t >= from && this.t < to;
		}

		// Progress 0..1 through [from, to].
		k(from, to) {
			return clamp01((this.t - from) / (to - from));
		}

		// The phase the timeline is in.
		phase() {
			const phases = this.def.phases || [];
			for (let i = phases.length - 1; i >= 0; i--) if (this.t >= phases[i].at) return phases[i];
			return phases[0] || { name: '', at: 0 };
		}

		emit(p) {
			p.age = 0;
			p.vx = p.vx || 0;
			p.vy = p.vy || 0;
			// Nothing outlives the timeline: the last frame is always empty.
			p.life = Math.min(p.life || 0.5, this.duration - this.t - 3 * TICK);
			if (p.life <= 0) return p;
			this.parts.push(p);
			this.stats.born++;
			return p;
		}

		burst(count, make) {
			for (let i = 0; i < count; i++) this.emit(make(i, count));
		}

		step() {
			const dt = TICK;
			for (const layer of this.layers) if (layer.persist || layer.fire) layer.tick(this.rng);
			this.def.update(this, this.t, dt);
			const parts = this.parts;
			for (let i = parts.length - 1; i >= 0; i--) {
				const p = parts[i];
				p.age += dt;
				if (p.age >= p.life) {
					parts.splice(i, 1);
					this.stats.died++;
					if (p.onDeath) p.onDeath(p, this);
					continue;
				}
				if (p.delay && p.age < p.delay) continue;
				p.px = p.x;
				p.py = p.y;
				if (p.move) {
					p.move(p, dt, this);
				} else {
					if (p.gravity) p.vy += p.gravity * dt;
					if (p.turb) {
						p.vx += (noise3(p.x * 0.07, p.y * 0.07, this.t * 1.5 + 11) - 0.5) * p.turb * dt;
						p.vy += (noise3(p.x * 0.07 + 40, p.y * 0.07, this.t * 1.5) - 0.5) * p.turb * dt;
					}
					if (p.drag) {
						const keep = Math.exp(-p.drag * dt);
						p.vx *= keep;
						p.vy *= keep;
					}
					p.x += p.vx * dt;
					p.y += p.vy * dt;
					if (p.floor !== undefined && p.y > p.floor) {
						p.y = p.floor;
						p.vy = -p.vy * (p.bounce || 0);
						p.vx *= 0.6;
						if (Math.abs(p.vy) < 12) p.vy = 0;
					}
				}
				if (p.trail) p.trail.plot(p.x, p.y, curve(p.trailHeat === undefined ? 0.5 : p.trailHeat, p.age / p.life));
			}
			this.stats.alive = parts.length;
			this.stats.peak = Math.max(this.stats.peak, parts.length);
			this.t += dt;
			this.ticks++;
		}

		drawParticle(p) {
			if (p.delay && p.age < p.delay) return;
			const k = p.age / p.life;
			const layer = p.layer;
			if (layer.kind === 'color') {
				// Dying pixels blink out instead of fading: alpha stays pixel-crisp.
				if (p.blink && k > p.blink && Math.floor(p.age * 30) % 2 === 0) return;
				const size = Math.round(curve(p.size === undefined ? 1 : p.size, k));
				if (p.shape === 'star') {
					const arm = Math.round(curve(p.size, k));
					layer.px(p.x, p.y, [1, 1, 1]);
					for (let d = 1; d <= arm; d++) {
						const c = d === arm && arm > 1 ? p.color : [1, 1, 1];
						layer.px(p.x + d, p.y, c);
						layer.px(p.x - d, p.y, c);
						layer.px(p.x, p.y + d, c);
						layer.px(p.x, p.y - d, c);
					}
					return;
				}
				for (let dy = 0; dy < size; dy++) for (let dx = 0; dx < size; dx++) layer.px(p.x + dx, p.y + dy, p.color);
				return;
			}
			const heat = curve(p.heat === undefined ? 1 : p.heat, k);
			if (heat <= 0) return;
			if (p.streak) {
				layer.line(p.x - p.vx * p.streak, p.y - p.vy * p.streak, p.x, p.y, heat * 0.35, heat);
				return;
			}
			const size = curve(p.size === undefined ? 0.5 : p.size, k);
			layer.disc(p.x, p.y, size, heat, p.soft, p.sy);
		}

		// Renders the current state into `out` (Uint8ClampedArray, RGBA).
		render(out) {
			for (const layer of this.layers) if (!layer.persist && !layer.fire) layer.clear();
			if (this.def.draw) this.def.draw(this, this.t);
			for (const p of this.parts) this.drawParticle(p);
			const acc = this.acc;
			acc.fill(0);
			for (const layer of this.layers) if (layer.visible) layer.composite(acc, this.t);
			for (let i = 0; i < this.w * this.h; i++) {
				const j = i * 4;
				const a = Math.min(1, acc[j + 3]);
				if (a <= 0.004) {
					out[j] = out[j + 1] = out[j + 2] = out[j + 3] = 0;
					continue;
				}
				out[j] = Math.min(255, (acc[j] / a) * 255);
				out[j + 1] = Math.min(255, (acc[j + 1] / a) * 255);
				out[j + 2] = Math.min(255, (acc[j + 2] / a) * 255);
				out[j + 3] = a * 255;
			}
			return out;
		}

		// Advances the timeline by one output frame.
		advanceFrame() {
			const ticks = Math.round(1 / (this.fps * TICK));
			for (let i = 0; i < ticks; i++) this.step();
		}
	}

	// Every frame of an effect, as an array of RGBA buffers.
	function renderFrames(def, seed) {
		const sim = new Sim(def, seed);
		const frames = [];
		for (let i = 0; i < def.frames; i++) {
			sim.advanceFrame();
			frames.push(sim.render(new Uint8ClampedArray(def.w * def.h * 4)));
		}
		return { frames, stats: sim.stats };
	}

	// A jagged bolt from (x0, y0) to (x1, y1) by midpoint displacement.
	function bolt(layer, rng, x0, y0, x1, y1, jag, heat, depth) {
		if (depth === undefined) depth = 4;
		if (depth === 0) {
			layer.line(x0, y0, x1, y1, heat);
			return;
		}
		const mx = (x0 + x1) / 2 + rng.range(-jag, jag);
		const my = (y0 + y1) / 2 + rng.range(-jag, jag);
		bolt(layer, rng, x0, y0, mx, my, jag * 0.55, heat, depth - 1);
		bolt(layer, rng, mx, my, x1, y1, jag * 0.55, heat, depth - 1);
		if (depth >= 3 && rng() < 0.45) {
			bolt(layer, rng, mx, my, mx + rng.range(-jag, jag) * 2.2, my + rng.range(-jag, jag) * 2.2, jag * 0.5, heat * 0.7, depth - 2);
		}
	}

	const PixelFX = { TICK, Sim, Layer, makeRng, noise3, fbm, ease, curve, clamp01, lerp, hex, ramp, RAMPS, renderFrames, bolt, effects: {} };
	root.PixelFX = PixelFX;
	if (typeof module !== 'undefined' && module.exports) module.exports = PixelFX;
})(typeof globalThis !== 'undefined' ? globalThis : this);
