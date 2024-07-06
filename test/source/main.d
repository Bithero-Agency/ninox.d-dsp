module app.main;

import std.stdio;
import std.variant : Variant;

import ninox.dsp : Context;
import app.page1 : renderTemplate;

void emit(const char[] text) {
	write(text);
}

void main() {
	Variant[string] data;
	data["items"] = [ 1, 22, 42 ];
	data["title"] = "aaa";

	Context ctx = Context(&emit, data);
	renderTemplate(ctx);
}
