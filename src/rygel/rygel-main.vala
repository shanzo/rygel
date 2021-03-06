/*
 * Copyright (C) 2008 Nokia Corporation.
 * Copyright (C) 2008 Zeeshan Ali (Khattak) <zeeshanak@gnome.org>.
 *
 * Author: Zeeshan Ali (Khattak) <zeeshanak@gnome.org>
 *
 * This file is part of Rygel.
 *
 * Rygel is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * Rygel is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 */

using CStuff;
using Gee;

public class Rygel.Main : Object {
    private PluginLoader plugin_loader;
    private RootDeviceFactory device_factory;
    private ArrayList<RootDevice> root_devices;

    private MainLoop main_loop;

    private int exit_code;

    public Main () throws GLib.Error {
        Environment.set_application_name (_(BuildConfig.PACKAGE_NAME));

        this.root_devices = new ArrayList<RootDevice> ();
        this.plugin_loader = new PluginLoader ();
        this.device_factory = new RootDeviceFactory ();
        this.main_loop = new GLib.MainLoop (null, false);

        this.exit_code = 0;

        this.plugin_loader.plugin_available += this.on_plugin_loaded;

        Utils.on_application_exit (this.application_exit_cb);
    }

    public int run () {
        this.plugin_loader.load_plugins ();

        this.main_loop.run ();

        return this.exit_code;
    }

    public void exit (int exit_code) {
        this.exit_code = exit_code;
        this.main_loop.quit ();
    }

    private void application_exit_cb () {
        this.exit (0);
    }

    private void on_plugin_loaded (PluginLoader plugin_loader,
                                   Plugin       plugin) {
        try {
            var device = this.device_factory.create (plugin);

            device.available = plugin.available;

            root_devices.add (device);

            plugin.notify["available"] += this.on_plugin_notify;
        } catch (GLib.Error error) {
            warning ("Failed to create RootDevice for %s. Reason: %s\n",
                     plugin.name,
                     error.message);
        }
    }

    private void on_plugin_notify (Plugin    plugin,
                                   ParamSpec spec) {
        foreach (var device in this.root_devices) {
            if (device.resource_factory == plugin) {
                device.available = plugin.available;
            }
        }
    }

    public static int main (string[] args) {
        Main main;
        DBusService service;

        try {
            // Parse commandline options
            CmdlineConfig.parse_args (ref args);

            // initialize gstreamer
            var dummy_args = new string[0];
            Gst.init (ref dummy_args);

            main = new Main ();
            service = new DBusService (main);
        } catch (CmdlineConfigError.VERSION_ONLY err) {
            return 0;
        } catch (GLib.Error err) {
            error ("%s", err.message);

            return -1;
        }

        int exit_code = main.run ();

        return exit_code;
    }
}

