# Chat Folders Panel UI Analysis

## Overview
The chat folders panel is a horizontal tab bar that displays all chat folders with controls for:
- **Contacts button** (left side) - toggles contacts panel view
- **Folder tabs** (center) - "Все чаты" (All chats) + individual folder tabs
- **Add folder button** (right side) - creates new folders

---

## 1. Primary Rendering Location

### File: `lib/screens/chats_screen.dart`

#### Method: `_buildFolderTabs()` (Lines 3727-3909)
This is the **main UI widget** that renders the entire folder panel.

**Structure:**
- **Container** (Line 3801-3908)
  - Height: 48px
  - Decoration: Surface color with border (or gradient/image from ThemeProvider)
  - Child: **Stack** containing:

#### Left Side - Contacts Button (Lines 3818-3830)
```dart
IconButton(
  icon: Icons.people_outline,
  onPressed: () {
    setState(() => _isShowingContacts = !_isShowingContacts);
  },
  color: _isShowingContacts ? colors.primary : colors.onSurfaceVariant,
  size: 22,
)
```
- **Condition visible when:** Always visible (no hiding condition)
- **Toggles:** `_isShowingContacts` boolean to show/hide contacts panel

#### Center - Folder Tabs (Lines 3831-3891)
The TabBar displays:
- **"Все чаты"** tab (Line 3732-3740) - always first
- **Folder tabs** (Lines 3741-3760) - mapped from `_folders` list

**Responsive Layout:**
- **If folders ≤ 3:** Non-scrollable, centered TabBar (Line 3832-3860)
- **If folders > 3:** Scrollable TabBar with right padding for "+" button (Line 3861-3890)

**Tab Styling:**
- Label color: Primary color (active)
- Unselected color: onSurfaceVariant
- Underline indicator: 3px primary color
- Font: 14px, bold for active, normal for inactive

#### Right Side - Add Folder Button (Lines 3894-3905)
```dart
Positioned(
  right: 0,
  top: 0,
  bottom: 0,
  child: IconButton(
    icon: Icon(Icons.add, size: 20),
    onPressed: _showCreateFolderDialog,
    tooltip: 'Создать папку',
  ),
)
```
- **Condition visible when:** Always visible (no hiding condition)
- **Action:** Opens folder creation dialog

---

## 2. Integration into Screen Hierarchy

### AppBar Integration (Line 4579+)
The `_buildAppBar()` method creates the AppBar with the folder tabs as a **bottom widget**.

**Location in AppBar:**
Currently, the folder tabs appear to be rendered separately (not as AppBar bottom). Looking at the main build method...

### Main Content Integration (Lines 1932-1959)
The folder panel is **NOT directly in build()** - instead:
1. **AppBar** is built by `_buildAppBar()` (passed to ChatsScreenScaffold)
2. **Body content** contains:
   - Archive banner (if applicable)
   - **TabBarView** with folder pages (Line 1952-1956)

**Key question:** Where is `_buildFolderTabs()` actually called?

**Answer:** It appears to be called in `_buildAppBar()` as the AppBar's `bottom` widget.

---

## 3. State Management

### Key State Variables (Lines 115-143)

#### Folder-Related:
```dart
List<ChatFolder> _folders = [];           // List of all folders
String? _selectedFolderId;                // Currently selected folder ID
late TabController _folderTabController;  // Controls folder tab switching
bool _isShowingContacts = false;          // Contacts panel visibility
```

#### Related:
```dart
List<Chat> _allChats = [];                // All chats
List<Chat> _filteredChats = [];           // Filtered by current folder
Map<int, Contact> _contacts = {};        // Contact lookup map
int _myId;                                // Current user ID
bool _prefsLoaded = false;                // SharedPreferences ready
```

### Initialization (Lines 279-280)
```dart
_folderTabController = TabController(length: 1, vsync: this);
_folderTabController.addListener(_onFolderTabChanged);
```
- TabController initialized with length 1 (just "Все чаты")
- Updated when folders load via `_loadFolders()`

---

## 4. Folder Loading and Updates

### Loading Folders (Triggered Line 1879)
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  _loadFolders(snapshot.data!);
});
```

### Method: `_loadFolders()` 
(Not fully shown in excerpts, but referenced at line 1879)
- Fetches folders from payload
- Updates `_folders` list
- Updates TabController length to `1 + _folders.length`

---

## 5. Display Conditions and Visibility

### Panel Visibility Conditions

#### **ALWAYS VISIBLE:**
- Contacts button (left)
- Add folder button (right)

#### **CONDITIONALLY VISIBLE (Folder Tabs):**

**Condition 1: Not in search mode**
```dart
if (!_isSearchExpanded) ...
```
(Line 1936)

**Condition 2: Not showing contacts**
```dart
if (!_isShowingContacts) ...
```
(Line 1936)

**Condition 3: Has chats loaded and data ready**
```dart
if (snapshot.hasData && _chatsLoaded)
```
(Line 1847-1848)

### Combined Visibility Logic:
**Folder tabs and pagination are hidden when:**
1. ✗ Search is expanded (`_isSearchExpanded == true`)
2. ✗ Contacts panel is shown (`_isShowingContacts == true`)
3. ✗ Chats are still loading
4. ✗ No chats exist and no data loaded

**Otherwise:** Visible with TabBarView and folder pages

---

## 6. Theme Customization

### Background Styling (Lines 3762-3799)
```dart
final themeProvider = context.watch<ThemeProvider>();

BoxDecoration? folderTabsDecoration;
if (themeProvider.folderTabsBackgroundType == FolderTabsBackgroundType.gradient) {
  // Gradient background
} else if (themeProvider.folderTabsBackgroundType == FolderTabsBackgroundType.image) {
  // Image background
}
```

### Available Theme Options:
- **Gradient mode:** Two colors with linear gradient
- **Image mode:** File-based background image
- **Default:** Surface color with subtle border
- **Border:** 1px outline with 20% opacity

---

## 7. ChatFolder Model

### File: `lib/models/chat_folder.dart`

```dart
class ChatFolder {
  final String id;
  final String title;
  final String? emoji;              // Optional emoji icon
  final List<int>? include;         // Chat IDs to include
  final List<dynamic> filters;      // Filter rules
  final bool hideEmpty;             // Hide if no chats
  final List<ChatFolderWidget> widgets;
  final List<int>? favorites;
  final Map<String, dynamic>? filterSubjects;
  final List<int>? options;
}
```

### Key for UI:
- **`title`** - Displayed in tab
- **`emoji`** - Displayed before title (Line 3750-3752)
- **`id`** - Used for tab tracking (ValueKey)

---

## 8. Chat List Pages Integration

### File: `lib/screens/chat/widgets/chats_list_page.dart`

**Purpose:** Renders chat list for each folder

**Constructor Parameters:**
```dart
const ChatsListPage({
  required ChatFolder? folder,        // null = "Все чаты", else specific folder
  required List<Chat> allChats,
  required Map<int, Contact> contacts,
  required Function buildChatListItem,
  required Function chatBelongsToFolder,  // Determines if chat is in folder
});
```

**Filtering Logic (Lines 42-46):**
```dart
if (widget.folder != null && widget.chatBelongsToFolder != null) {
  chatsForFolder = widget.allChats
      .where((chat) => widget.chatBelongsToFolder!(chat, widget.folder!))
      .toList();
}
```

---

## 9. Related Files

### `lib/screens/chat/widgets/chats_screen_scaffold.dart`
- Wraps the ChatsScreen with Scaffold
- Takes `buildAppBar` callback to render AppBar
- No direct folder logic here

### `lib/screens/chat/widgets/chats_list_page.dart`
- Renders individual chat lists per folder
- Handles empty states
- Uses animated list transitions

### `lib/screens/chat/dialogs/add_chats_to_folder_dialog.dart`
- Dialog for adding chats to folders

---

## 10. Action Handlers

### Contacts Button (Line 3819-3820)
```dart
setState(() => _isShowingContacts = !_isShowingContacts);
```
- Toggles between contacts panel and folder tabs
- Changes icon color to primary when active

### Create Folder Button (Line 3900)
```dart
_showCreateFolderDialog()
```
- Opens AlertDialog (Lines 3911-3949)
- Takes folder name input
- Calls `ApiService.instance.createFolder(title)`

### Folder Tab Long-Press (Line 3744-3745)
```dart
onLongPress: () {
  _showFolderEditMenu(folder);
}
```
- Opens context menu for folder editing

---

## Summary: Where the Panel is Defined

| Component | Location | Lines | Condition |
|-----------|----------|-------|-----------|
| **Full Panel Widget** | `_buildFolderTabs()` | 3727-3909 | Always rendered in AppBar |
| **Contacts Button** | Left side | 3818-3830 | Always visible |
| **Folder Tabs (TabBar)** | Center | 3731-3890 | Hidden if search/contacts visible |
| **Add Folder Button** | Right side | 3894-3905 | Always visible |
| **Integration** | `_buildAppBar()` | 4579+ | AppBar bottom widget |
| **Body Content** | `build()` | 1932-1959 | Main TabBarView with folder pages |

---

## Key Display Conditions Summary

**The folder panel tabs are HIDDEN when:**
1. `_isSearchExpanded == true` → Show search UI instead
2. `_isShowingContacts == true` → Show contacts panel instead
3. Chats are loading → Show connection screen
4. No chats and not loaded → Show "Нет чатов" message

**The panel is ALWAYS SHOWN otherwise**, along with:
- Contacts button (always available)
- Add folder button (always available)
- Current folder's chat list in TabBarView
