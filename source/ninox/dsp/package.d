/*
 * Copyright (C) 2024 Mai-Lapyst
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/** 
 * Module to hold some runtime code for dsp templates.
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2024 Mai-Lapyst
 * Authors:   $(HTTP codearq.net/Mai-Lapyst, Mai-Lapyst)
 */
module ninox.dsp;

import std.variant : Variant;
import ninox.std.callable;

/// The rendering context given to the rendering functions of templates.
struct Context {
    Callable!(void, const char[]) emit;
    Variant data;

    this(T)(void function(const char[]) emit, T data) {
        this.emit = emit;
        this.data = data;
    }

    this(T)(void delegate(const char[]) emit, T data) {
        this.emit = emit;
        this.data = data;
    }

    this(T)(Callable!(void, const char[]) emit, T data) {
        this.emit = emit;
        this.data = data;
    }

    Context withData(T)(T data) {
        return Context(this.emit, data);
    }
}
