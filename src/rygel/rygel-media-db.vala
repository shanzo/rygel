/*
 * Copyright (C) 2009 Jens Georg <mail@jensge.org>.
 *
 * Author: Jens Georg <mail@jensge.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 */

using Gee;
using Sqlite;

public errordomain Rygel.MediaDBError {
    SQLITE_ERROR,
    GENERAL_ERROR
}

public enum Rygel.MediaDBObjectType {
    CONTAINER,
    ITEM
}

public class Rygel.MediaDB : Object {
    private Database db;
    private MediaDBObjectFactory factory;
    private const string schema_version = "3";
    private const string db_schema_v1 =
    "BEGIN;" +
    "CREATE TABLE Schema_Info (version TEXT NOT NULL); " +
    "CREATE TABLE Object_Type (id INTEGER PRIMARY KEY, " +
                              "desc TEXT NOT NULL);" +
    "CREATE TABLE Meta_Data (id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                            "size INTEGER NOT NULL, " +
                            "mime_type TEXT NOT NULL, " +
                            "duration INTEGER, " +
                            "width INTEGER, " +
                            "height INTEGER, " +
                            "class TEXT NOT NULL, " +
                            "author TEXT, " +
                            "album TEXT, " +
                            "date TEXT, " +
                            "bitrate INTEGER, " +
                            "sample_freq INTEGER, " +
                            "bits_per_sample INTEGER, " +
                            "channels INTEGER, " +
                            "track, " +
                            "color_depth);" +
    "CREATE TABLE Object (parent TEXT REFERENCES Object(upnp_id), " +
                         "upnp_id TEXT PRIMARY KEY, " +
                         "type_fk INTEGER REFERENCES Object_Type(id), " +
                         "title TEXT NOT NULL, " +
                         "metadata_fk INTEGER REFERENCES Meta_Data(id) " +
                         "ON DELETE CASCADE);" +
    "CREATE TABLE Uri (object_fk TEXT REFERENCES Object(upnp_id), "+
                      "uri TEXT NOT NULL);" +
    "INSERT INTO Object_Type (id, desc) VALUES (0, 'Container'); " +
    "INSERT INTO Object_Type (id, desc) VALUES (1, 'Item'); " +
    "INSERT INTO Schema_Info (version) VALUES ('" + MediaDB.schema_version +
                                                "'); " +
    "END;";

    private const string INSERT_META_DATA_STRING =
    "INSERT INTO Meta_Data " +
        "(size, mime_type, width, height, class, " +
         "author, album, date, bitrate, " +
         "sample_freq, bits_per_sample, channels, " +
         "track, color_depth, duration) VALUES " +
         "(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";

    private const string INSERT_OBJECT_STRING =
    "INSERT INTO Object (upnp_id, title, type_fk, metadata_fk, parent) " +
        "VALUES (?,?,?,?,?)";

    private const string INSERT_URI_STRING =
    "INSERT INTO Uri (object_fk, uri) VALUES (?,?)";

    private const string GET_OBJECT_STRING =
    "SELECT type_fk, title, Meta_Data.size, Meta_Data.mime_type, " +
            "Meta_Data.width, Meta_Data.height, " +
            "Meta_Data.class, Meta_Data.author, Meta_Data.album, " +
            "Meta_Data.date, Meta_Data.bitrate, Meta_Data.sample_freq, " +
            "Meta_Data.bits_per_sample, Meta_Data.channels, " +
            "Meta_Data.track, Meta_Data.color_depth, Meta_Data.duration, " +
            "Object.parent " +
    "FROM Object LEFT OUTER JOIN Meta_Data " +
        "ON Object.metadata_fk = Meta_Data.id WHERE Object.upnp_id = ?";

    private const string GET_CHILDREN_STRING =
    "SELECT type_fk, title, Meta_Data.size, Meta_Data.mime_type, " +
            "Meta_Data.width, Meta_Data.height, " +
            "Meta_Data.class, Meta_Data.author, Meta_Data.album, " +
            "Meta_Data.date, Meta_Data.bitrate, Meta_Data.sample_freq, " +
            "Meta_Data.bits_per_sample, Meta_Data.channels, " +
            "Meta_Data.track, Meta_Data.color_depth, Meta_Data.duration, " +
            "upnp_id, Object.parent " +
    "FROM Object LEFT OUTER JOIN Meta_Data " +
        "ON Object.metadata_fk = Meta_Data.id " +
    "WHERE Object.parent = ? " +
        "ORDER BY Meta_Data.track ASC, title ASC " +
    "LIMIT ?,?";

    private const string URI_GET_STRING =
    "SELECT uri FROM Uri WHERE Uri.object_fk = ?";

    private const string CHILDREN_COUNT_STRING =
    "SELECT COUNT(upnp_id) FROM Object WHERE Object.parent = ?";

    private const string OBJECT_EXISTS_STRING =
    "SELECT COUNT(upnp_id) FROM Object WHERE Object.upnp_id = ?";

    private void open_db (string name) {
        var dirname = Path.get_dirname (name);
        DirUtils.create_with_parents (dirname, 0750);
        var rc = Database.open (name, out this.db);
        if (rc != Sqlite.OK) {
            warning ("Failed to open database: %d, %s",
                     rc,
                     db.errmsg ());
            return;
        }

        weak string[] schema_info;
        int nrows;
        int ncolumns;
        // FIXME error message causes segfault
        rc = db.get_table ("SELECT version FROM Schema_Info;",
                           out schema_info,
                           out nrows,
                           out ncolumns,
                           null);

        if (rc == Sqlite.OK) {
            if (nrows == 1 && ncolumns == 1) {
                if (schema_info[1] == schema_version) {
                    debug ("Media DB schema has current version");
                } else {
                    debug ("Schema version differs... checking for upgrade");
                    // FIXME implement if necessary
                }
            } else {
                warning ("Incompatible schema... cannot proceed");
                db = null;
                return;
            }
        } else {
            debug ("Could not find schema version; checking for empty database...");
            rc = db.get_table ("SELECT * FROM sqlite_master",
                               out schema_info,
                               out nrows,
                               out ncolumns,
                               null);
            if (rc != Sqlite.OK) {
                warning ("Something weird going on: %s",
                         db.errmsg ());
                db = null;
                return;
            }

            if (nrows == 0) {
                debug ("Empty database, creating new schema version %s",
                       schema_version);
                if (!create_schema ()) {
                    return;
                }
            } else {
                warning ("Incompatible schema... cannot proceed");
                return;
            }
        }
    }

    public MediaDB (string name) {
        open_db (name);
        this.factory = new MediaDBObjectFactory ();
    }

    public MediaDB.with_factory (string name, MediaDBObjectFactory factory) {
        open_db (name);
        this.factory = factory;
    }

    public signal void item_added (string item_id);

    public void save_object (MediaObject obj) throws Error {
        if (obj is MediaItem) {
            save_item ((MediaItem)obj);
        } else if (obj is MediaContainer) {
            save_container ((MediaContainer)obj);
        } else {
            throw new MediaDBError.GENERAL_ERROR ("Invalid object type");
        }
    }

    public void save_container (MediaContainer container) throws Error {
        var rc = db.exec ("BEGIN");
        try {
            create_object (container, -1);
            save_uris (container);
            rc = db.exec ("COMMIT");
        } catch (Error error) {
            rc = db.exec ("ROLLBACK");
        }
    }

    public void save_item (MediaItem item) throws Error {
        var rc = db.exec ("BEGIN;");
        try {
            var id = save_metadata (item);
            create_object (item, id);
            save_uris (item);
            rc = db.exec ("COMMIT;");
            if (rc == Sqlite.OK) {
                item_added (item.id);
            }
        } catch (Error error) {
            warning ("Failed to add item with id %s: %s",
                     item.id,
                     error.message);
            rc = db.exec ("ROLLBACK;");
        }
    }

    private int64 save_metadata (MediaItem item) throws Error {
        Statement statement;
        var rc = db.prepare_v2 (INSERT_META_DATA_STRING,
                                -1,
                                out statement,
                                null);
        if (rc == Sqlite.OK) {
            statement.bind_int64 (1, item.size);
            statement.bind_text (2, item.mime_type);
            statement.bind_int (3, item.width);
            statement.bind_int (4, item.height);
            statement.bind_text (5, item.upnp_class);
            statement.bind_text (6, item.author);
            statement.bind_text (7, item.album);
            statement.bind_text (8, item.date);
            statement.bind_int (9, item.bitrate);
            statement.bind_int (10, item.sample_freq);
            statement.bind_int (11, item.bits_per_sample);
            statement.bind_int (12, item.n_audio_channels);
            statement.bind_int (13, item.track_number);
            statement.bind_int (14, item.color_depth);
            statement.bind_int64 (15, item.duration);

            rc = statement.step ();
            if (rc == Sqlite.DONE || rc == Sqlite.OK) {
                return db.last_insert_rowid ();
            } else {
                throw new MediaDBError.SQLITE_ERROR (db.errmsg ());
            }
        } else {
            throw new MediaDBError.SQLITE_ERROR (db.errmsg ());
        }
    }

    private void create_object (MediaObject item, int64 metadata_id) throws Error {
        Statement statement;

        var rc = db.prepare_v2 (INSERT_OBJECT_STRING,
                            -1,
                            out statement,
                            null);
        if (rc == Sqlite.OK) {
            statement.bind_text (1, item.id);
            statement.bind_text (2, item.title);

            if (item is MediaItem) {
                statement.bind_int (3, MediaDBObjectType.ITEM);
            } else if (item is MediaObject) {
                statement.bind_int (3, MediaDBObjectType.CONTAINER);
            } else {
                throw new MediaDBError.GENERAL_ERROR ("Invalid object type");
            }

            if (metadata_id == -1) {
                statement.bind_null (4);
            } else {
                statement.bind_int64 (4, metadata_id);
            }

            if (item.parent == null) {
                statement.bind_null (5);
            } else {
                statement.bind_text (5, item.parent.id);
            }
            rc = statement.step ();
            if (rc != Sqlite.OK && rc != Sqlite.DONE) {
                throw new MediaDBError.SQLITE_ERROR (db.errmsg ());
            }
        } else {
            throw new MediaDBError.SQLITE_ERROR (db.errmsg ());
        }
    }

    private void save_uris (MediaObject obj) throws Error {
        Statement statement;

        var rc = db.prepare_v2 (INSERT_URI_STRING,
                                -1,
                                out statement,
                                null);
        if (rc == Sqlite.OK) {
            foreach (var uri in obj.uris) {
                statement.bind_text (1, obj.id);
                statement.bind_text (2, uri);
                rc = statement.step ();
                if (rc != Sqlite.OK && rc != Sqlite.DONE) {
                    throw new MediaDBError.SQLITE_ERROR (db.errmsg ());
                }
                statement.reset ();
                statement.clear_bindings ();
            }
        } else {
            throw new MediaDBError.SQLITE_ERROR (db.errmsg ());
        }
    }

    /**
     * Create the current schema.
     *
     * If schema creation fails, schema will be rolled back
     * completely.
     *
     * @returns: true on success, false on failure
     */
    private bool create_schema () {
        var rc = db.exec (db_schema_v1);
        if (rc == Sqlite.OK) {
            debug ("Schema created");
            return true;
        } else {
            warning ("Could not create schema: %d, %s",
                     rc,
                     db.errmsg ());
            rc = db.exec ("ROLLBACK;");
            return false;
        }
    }

    private void add_uris (MediaObject obj) {
        Statement statement;

        var rc = db.prepare_v2 (URI_GET_STRING,
                                -1,
                                out statement,
                                null);
        if (rc == Sqlite.OK) {
            statement.bind_text (1, obj.id);
            while ((rc = statement.step ()) == Sqlite.ROW) {
                obj.uris.add (statement.column_text (0));
            }
        } else {
            warning ("Failed to get uris for obj %s: %s",
                     obj.id,
                     db.errmsg ());
        }
    }

    private MediaObject? get_object_from_statement (MediaContainer? parent, string object_id, Statement statement) {
        MediaObject obj = null;
        switch (statement.column_int (0)) {
            case 0:
                // this is a container
                obj = factory.get_container (this,
                        object_id,
                        statement.column_text (1),
                        0);
                break;
            case 1:
                // this is an item
                obj = factory.get_item (this,
                        parent,
                        object_id,
                        statement.column_text (1),
                        statement.column_text (6));
                fill_item (statement, (MediaItem)obj);
                break;
            default:
                // should not happen
                break;
        }

        if (obj != null) {
            add_uris (obj);
        }
        return obj;
    }

    public MediaObject? get_object (string object_id) {
        MediaObject obj = null;
        Statement statement;

        // decide what kind of object this is
        var rc = db.prepare_v2 (GET_OBJECT_STRING,
                                -1,
                                out statement,
                                null);
        if (rc == Sqlite.OK) {
            statement.bind_text (1, object_id);
            while ((rc = statement.step ()) == Sqlite.ROW) {
                var parent = get_object (statement.column_text (17));
                obj = get_object_from_statement ((MediaContainer)parent, object_id, statement);
                obj.parent_ref = (MediaContainer)parent;
                obj.parent = obj.parent_ref;
                break;
            }
        } else {
        }

        return obj;
    }

    private void fill_item (Statement statement, MediaItem item) {
        item.author = statement.column_text (7);
        item.album = statement.column_text (8);
        item.date = statement.column_text (9);
        item.mime_type = statement.column_text (3);
        item.duration = (long)statement.column_text (16);

        item.size = (long)statement.column_int64 (2);
        item.bitrate = statement.column_int (10);

        item.sample_freq = statement.column_int(11);
        item.bits_per_sample = statement.column_int (12);
        item.n_audio_channels = statement.column_int (13);
        item.track_number = statement.column_int (14);

        item.width = statement.column_int (4);
        item.height = statement.column_int (5);
        item.color_depth = statement.column_int (15);
    }

    public int get_child_count (string object_id) {
        Statement statement;
        int count = 0;
        var rc = db.prepare_v2 (CHILDREN_COUNT_STRING,
                                -1,
                                out statement,
                                null);
        if (rc == Sqlite.OK) {
            statement.bind_text (1, object_id);
            while ((rc = statement.step ()) == Sqlite.ROW) {
                count = statement.column_int (0);
                break;
            }
        } else {
            warning ("Could not get child count for object %s: %s",
                     object_id,
                     db.errmsg ());
        }

        return count;
    }

    public bool exists (string object_id) {
        Statement statement;
        bool exists = false;
        var rc = db.prepare_v2 (OBJECT_EXISTS_STRING,
                                -1,
                                out statement,
                                null);
        if (rc == Sqlite.OK) {
            statement.bind_text (1, object_id);
            while ((rc = statement.step ()) == Sqlite.ROW) {
                exists = statement.column_int (0) == 1;
                break;
            }
        } else {
            warning ("Could not get child count for object %s: %s",
                     object_id,
                     db.errmsg ());
        }

        return exists;
    }


    public Gee.ArrayList<MediaObject> get_children (string object_id,
                                                      uint offset,
                                                      uint max_count) {
        Statement statement;
        Gee.ArrayList<MediaObject> children =
                                            new Gee.ArrayList<MediaObject> ();
        var rc = db.prepare_v2 (GET_CHILDREN_STRING,
                                -1,
                                out statement,
                                null);
        if (rc == Sqlite.OK) {
            statement.bind_text (1, object_id);
            statement.bind_int64 (2, (int64)offset);
            statement.bind_int64 (3, (int64)max_count);
            while ((rc = statement.step ()) == Sqlite.ROW) {
                var child_id = statement.column_text (17);
                var parent = get_object (statement.column_text (18));
                children.add (get_object_from_statement
                ((MediaContainer)parent, child_id, statement));
                children[children.size - 1].parent = (MediaContainer)parent;
                children[children.size - 1].parent_ref = (MediaContainer)parent;
            }
        }

        return children;
    }
}
