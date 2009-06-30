plugindir = $(libdir)/rygel-1.0

plugin_LTLIBRARIES = librygel-youtube.la

AM_CFLAGS = $(LIBGUPNP_CFLAGS) \
	    $(LIBGUPNP_AV_CFLAGS) \
	    $(LIBDBUS_GLIB_CFLAGS) \
	    $(GEE_CFLAGS) \
	    $(LIBGSTREAMER_CFLAGS) \
	    $(LIBGCONF_CFLAGS) \
	    -I$(top_srcdir)/src/rygel -DDATA_DIR='"$(datadir)"'

BUILT_SOURCES = rygel-youtube-content-dir.c \
		rygel-youtube-root-container.c \
		rygel-youtube-item.c \
		rygel-youtube-audio-item.c \
		rygel-youtube-video-item.c \
		rygel-youtube-plugin.c

$(BUILT_SOURCES) : rygel-youtube.stamp

librygel_youtube_la_SOURCES = rygel-youtube-content-dir.c \
			   rygel-youtube-content-dir.vala \
			   rygel-youtube-root-container.c \
			   rygel-youtube-root-container.vala \
			   rygel-youtube-item.c \
			   rygel-youtube-item.vala \
			   rygel-youtube-audio-item.c \
			   rygel-youtube-audio-item.vala \
			   rygel-youtube-video-item.c \
			   rygel-youtube-video-item.vala \
			   rygel-youtube-plugin.c \
			   rygel-youtube-plugin.vala

rygel-youtube.stamp: $(filter %.vala,$(librygel_youtube_la_SOURCES))
	$(VALAC) -C --vapidir=$(top_srcdir)/src/rygel \
	--pkg rygel-1.0 --pkg cstuff --pkg gconf-2.0 \
	--pkg gupnp-1.0 --pkg gupnp-av-1.0 \
        --pkg dbus-glib-1 --pkg gee-1.0 --pkg gstreamer-0.10 $^
	touch $@

librygel_youtube_la_LIBADD = $(LIBGUPNP_LIBS) \
			  $(LIBGUPNP_AV_LIBS) \
                          $(LIBDBUS_GLIB_LIBS) \
	                  $(LIBGSTREAMER_LIBS) \
                          $(GEE_LIBS) \
			  $(LIBGCONF_LIBS)
librygel_youtube_la_LDFLAGS = -shared -fPIC -module -avoid-version

CLEANFILES = rygel-youtube.stamp
MAINTAINERCLEANFILES = Makefile.in $(BUILT_SOURCES)
EXTRA_DIST = $(BUILT_SOURCES) rygel-youtube.stamp
