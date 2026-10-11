#!/usr/bin/env node
// Renders every effect of effects.js into a sprite sheet and writes the
// "Pixel FX" resource pack around them:
//
//   node tools/fx_studio/export.js            -> packs/pixelfx/ (and the title
//                                                into packs/default/)
//   node tools/fx_studio/export.js <folder>   -> another pack folder
//   node tools/fx_studio/export.js --pack icon -> packs/icon/: the effects in
//                                                that pack's colors and its
//                                                own backdrop
//
// Output: fx/<event>.png (frames left to right, top to bottom), pack.png (the
// icon) and pack.json with one "effects" entry per sheet. Deterministic: the
// same sources always give the same pixels.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const FX = require('./effects.js');

const SHEET_WIDTH = 1536;

function png(width, height, rgba) {
	const chunk = (type, data) => {
		const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
		const out = Buffer.alloc(body.length + 8);
		out.writeUInt32BE(data.length, 0);
		body.copy(out, 4);
		out.writeUInt32BE(zlib.crc32(body) >>> 0, body.length + 4);
		return out;
	};
	const header = Buffer.alloc(13);
	header.writeUInt32BE(width, 0);
	header.writeUInt32BE(height, 4);
	header.set([8, 6, 0, 0, 0], 8);
	const raw = Buffer.alloc((width * 4 + 1) * height);
	for (let y = 0; y < height; y++) Buffer.from(rgba.buffer, y * width * 4, width * 4).copy(raw, y * (width * 4 + 1) + 1);
	return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

function sheet(def, frames) {
	const columns = Math.min(frames.length, Math.max(1, Math.floor(SHEET_WIDTH / def.w)));
	const rows = Math.ceil(frames.length / columns);
	const width = columns * def.w, height = rows * def.h;
	const out = new Uint8ClampedArray(width * height * 4);
	frames.forEach((frame, index) => {
		const ox = (index % columns) * def.w, oy = Math.floor(index / columns) * def.h;
		for (let y = 0; y < def.h; y++) out.set(frame.subarray(y * def.w * 4, (y + 1) * def.w * 4), ((oy + y) * width + ox) * 4);
	});
	return { width, height, columns, data: out };
}

function coverage(frame) {
	let lit = 0;
	for (let i = 3; i < frame.length; i += 4) if (frame[i] > 0) lit++;
	return lit;
}

// The icon: the hottest moment of the showpiece, cropped and halved.
function icon(def, frames) {
	let best = frames[0];
	for (const frame of frames) if (coverage(frame) > coverage(best)) best = frame;
	const size = 64, out = new Uint8ClampedArray(size * size * 4);
	const backdrop = [10, 12, 22, 255];
	for (let y = 0; y < size; y++) {
		for (let x = 0; x < size; x++) {
			const sx = Math.floor(def.w / 2 - size + x * 2), sy = Math.floor(def.h * 0.5 - size + y * 2);
			const j = (sy * def.w + sx) * 4, a = best[j + 3] / 255;
			for (let c = 0; c < 3; c++) out[(y * size + x) * 4 + c] = best[j + c] * a + backdrop[c] * (1 - a);
			out[(y * size + x) * 4 + 3] = 255;
		}
	}
	return png(size, size, out);
}

// The loops (the title and the backdrop) belong to the default pack - every
// pack may bring its own: the sheet goes there and its entry in pack.json is
// rewritten in place. Exporting anywhere else just writes the sheet next to
// the effects.
function writeLoop(target, def, made, stats) {
	const key = def.kind, file = key + '.png';
	const entry = { sheet: file, frame: [def.w, def.h], frames: def.frames, fps: def.fps };
	if (key === 'title') Object.assign(entry, { scale: def.scale, loop_from: def.loopFrom, glow: 0.3 });
	const line = '"' + key + '": ' + JSON.stringify(entry).replace(/,"/g, ', "').replace(/":/g, '": ');
	const home = path.join(target, '..', 'default');
	const manifest = path.join(home, 'pack.json');
	let where = target;
	if (path.basename(target) === 'pixelfx' && fs.existsSync(manifest)) {
		where = home;
		let text = fs.readFileSync(manifest, 'utf8');
		const old = new RegExp('\\n\\t"' + key + '": \\{.*\\}(,?)\\n');
		text = old.test(text) ? text.replace(old, '\n\t' + line + '$1\n') : text.replace('\n\t"fonts": {', '\n\t' + line + ',\n\t"fonts": {');
		fs.writeFileSync(manifest, text);
	}
	fs.writeFileSync(path.join(where, file), png(made.width, made.height, made.data));
	console.log('%s  %dx%d  %d frames @ %d fps, loops from %d  sheet %dx%d  particles born %d, peak %d  -> %s',
		def.name.padEnd(14), def.w, def.h, def.frames, def.fps, def.loopFrom, made.width, made.height, stats.born, stats.peak, where);
	return entry;
}

// A themed pack (--pack <id>) takes the board effects in its own colors:
// every pixel keeps its brightness and its place and is given the color of
// that brightness on the theme's ramp.
const THEMES = {
	icon: ['#2a0806', '#7a140c', '#b02a1a', '#d88a1c', '#e8b83a', '#ffe27a', '#fff6c8', '#ffffff'],
};

function recolor(frames, stops) {
	const ramp = stops.map(FX.hex);
	for (const frame of frames) {
		for (let i = 0; i < frame.length; i += 4) {
			if (frame[i + 3] === 0) continue;
			const light = (0.3 * frame[i] + 0.59 * frame[i + 1] + 0.11 * frame[i + 2]) / 255;
			const at = Math.min(ramp.length - 1.001, Math.pow(light, 0.85) * (ramp.length - 1));
			const low = Math.floor(at), k = at - low;
			for (let c = 0; c < 3; c++) frame[i + c] = Math.round((ramp[low][c] + (ramp[low + 1][c] - ramp[low][c]) * k) * 255);
		}
	}
}

function main() {
	const args = process.argv.slice(2);
	const theme = args[0] === '--pack' ? args[1] : null;
	if (theme && !THEMES[theme]) {
		console.log('no such themed pack: ' + theme + ' (known: ' + Object.keys(THEMES).join(', ') + ')');
		return 1;
	}
	const target = path.resolve(theme ? path.join(__dirname, '..', '..', 'packs', theme) : args[0] || path.join(__dirname, '..', '..', 'packs', 'pixelfx'));
	fs.mkdirSync(path.join(target, 'fx'), { recursive: true });
	const effects = {};
	const loops = {};
	let problems = 0;
	for (const def of FX.effectList) {
		const loop = def.kind === 'title' || def.kind === 'backdrop';
		// A pack's own loops go to that pack only; the board effects to all.
		if (loop ? (def.pack || null) !== theme : false) continue;
		const { frames, stats } = FX.renderFrames(def);
		if (theme && !loop) recolor(frames, THEMES[theme]);
		const made = sheet(def, frames);
		if (loop) {
			loops[def.kind] = writeLoop(target, def, made, stats);
			continue;
		}
		fs.writeFileSync(path.join(target, 'fx', def.name + '.png'), png(made.width, made.height, made.data));
		effects[def.name] = { sheet: 'fx/' + def.name + '.png', frame: [def.w, def.h], frames: def.frames, fps: def.fps, scale: def.scale, anchor: def.anchor, glow: 0.35, replace: true };
		const left = coverage(frames[frames.length - 1]), first = coverage(frames[0]);
		const warn = left > 0 ? '  !! last frame still has ' + left + ' pixels' : '';
		if (left > 0 || first === 0) problems++;
		console.log('%s  %dx%d  %d frames (%s s)  sheet %dx%d  particles born %d, peak %d%s%s',
			def.name.padEnd(14), def.w, def.h, def.frames, (def.frames / def.fps).toFixed(2), made.width, made.height, stats.born, stats.peak,
			first === 0 ? '  !! first frame is empty' : '', warn);
		if (def.name === 'ko' && !theme) fs.writeFileSync(path.join(target, 'pack.png'), icon(def, frames));
	}
	// A themed pack has its own pack.json (colors, blocks, ...): only the
	// moving parts are written into it.
	const file = path.join(target, 'pack.json');
	const manifest = theme && fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {
		format: 1,
		name: 'Pixel FX',
		author: 'Project',
		description: 'Hand-timed pixel animations for every board event: line clears, Tetris, T-spins, perfect clears, drops, garbage and the K.O. Made with tools/fx_studio.',
	};
	manifest.effects = effects;
	if (theme) Object.assign(manifest, loops);
	fs.writeFileSync(file, JSON.stringify(manifest, null, '\t').replace(/\[\n\t+(\d+),\n\t+(\d+)\n\t+\]/g, '[$1, $2]') + '\n');
	console.log(problems ? problems + ' effect(s) need attention' : 'ok -> ' + target);
	return problems ? 1 : 0;
}

process.exit(main());
