#!/bin/bash
export G_MESSAGES_DEBUG=""
export G_DEBUG=""
flutter run -d linux 2>&1 | grep -v "Gdk-WARNING" | grep -v "Error converting selection"

