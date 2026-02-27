# Flutter ChatsScreen Folder Tabs Analysis

## Summary
The folder tabs in `chats_screen.dart` are **always rendered** - there's no condition that hides them when folders are empty or not loaded. The tabs panel is built once and displayed permanently.

---

## 1. TabController Initialization

**Location:** `lib/screens/chats_screen.dart`, lines 279-280 in `initState()`

```dart
_folderTabController = TabController(length: 1, vsync: this);
_folderTabController.addListener(_onFolderTabChanged);
```

- Initialized with `length: 1` (just the "All Chats" tab initially)
- Updated dynamically when folders are loaded via `_updateFolderTabController()` (lines 1052-1065)

---

## 2. The `_buildFolderTabs()` Method

**Location:** `lib/screens/chats_screen.dart`, lines 3728-3927

**Key Points:**
- **Always shown** - comment on line 3729 states: "Показываем панель всегда, даже если папки еще не загружены" (We show the panel always, even if folders are not yet loaded)
- Fixed height of 48 pixels
- Contains:
  - People/Contacts toggle button (left)
  - TabBar with folder tabs
  - Add folder button (+) on the right
  - Supports custom background (solid color, gradient, or image)

```dart
Widget _buildFolderTabs() {
    // Показываем панель всегда, даже если папки еще не загружены
    final colors = Theme.of(context).colorScheme;

    final List<Widget> tabs = [
      Tab(
        child: GestureDetector(
          onLongPress: () {},
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('Все чаты', style: TextStyle(fontSize: 14))],
          ),
        ),
      ),
      ..._folders.map(
        (folder) => Tab(
          child: GestureDetector(
            onLongPress: () {
              _showFolderEditMenu(folder);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (folder.emoji != null) ...[
                  Text(folder.emoji!, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                ],
                Text(folder.title, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    ];

    final themeProvider = context.watch<ThemeProvider>();

    BoxDecoration? folderTabsDecoration;
    // ... decoration logic (gradient/image support) ...

    return Container(
      height: 48,
      decoration: folderTabsDecoration ?? BoxDecoration(...),
      child: Stack(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() => _isShowingContacts = !_isShowingContacts);
                },
                // ... contacts toggle button ...
              ),
              Expanded(
                child: _folders.length <= 3
                    ? Center(
                        child: TabBar(
                          controller: _folderTabController,
                          // ... centered tabs for <= 3 folders ...
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 48),
                        child: TabBar(
                          controller: _folderTabController,
                          isScrollable: true,
                          // ... scrollable tabs for > 3 folders ...
                        ),
                      ),
              ),
            ],
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: _showCreateFolderDialog,
              // ... add folder button ...
            ),
          ),
        ],
      ),
    );
  }
```

---

## 3. The `_buildAppBar()` Method

**Location:** `lib/screens/chats_screen.dart`, lines 4579-4700

**Note:** `_buildFolderTabs()` is **NOT called from `_buildAppBar()`**. The AppBar is separate.

The AppBar contains:
- Leading: Menu/back button
- Title: Search field or current title widget
- Actions: Search, downloads, Sferum button, filters
- Supports custom background (gradient/image)

---

## 4. Main `build()` Method

**Location:** `lib/screens/chats_screen.dart`, lines 1832-2000

**Structure:**
```dart
@override
Widget build(BuildContext context) {
    super.build(context);

    final Widget bodyContent = Stack(
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _chatsFuture,
          builder: (context, snapshot) {
            // ... data loading ...
            
            if (_isSearchExpanded) {
              return _buildSearchResults();
            } else {
              final isAllChatsTab = _folderTabController.index == 0;
              final showArchiveBanner = isAllChatsTab && 
                  _archivedChatsList.isNotEmpty && 
                  !_archiveBannerDismissed;
              
              return Column(
                children: [
                  if (_isShowingContacts)
                    Expanded(child: _buildContactsPanel()),
                  if (!_isShowingContacts) ...[
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: showArchiveBanner
                          ? GestureDetector(...)
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _folderTabController,
                        children: _buildFolderPages(),
                      ),
                    ),
                  ],
                ],
              );
            }
          },
        ),
        if (!_isSearchExpanded) _buildDebugRefreshPanel(context),
      ],
    );

    final content = widget.hasScaffold
        ? ChatsScreenScaffold(
            bodyContent: bodyContent,
            buildAppBar: _buildAppBar,
            buildAppDrawer: _buildAppDrawer,
            showFab: !_isShowingContacts,
            onAddPressed: widget.isForwardMode
                ? null
                : () => _showAddMenu(context),
          )
        : bodyContent;

    return PopScope(
      canPop: !_isSearchExpanded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSearchExpanded) {
          _clearSearch();
        }
      },
      child: content,
    );
}
```

---

## 5. Where Folder Tabs Are Rendered

**Key finding:** `_buildFolderTabs()` is defined but **NOT explicitly called in the build method shown**.

Instead, the UI structure uses:
1. **AppBar** (from `buildAppBar: _buildAppBar`) - displayed via `ChatsScreenScaffold`
2. **Body Content** - contains folder tabs implicitly through `TabBarView`

The folder tabs are rendered via the **folder pages builder** in `_buildFolderPages()` which works with `_folderTabController`.

---

## 6. Visibility Conditions

### ✅ Folder Tabs Are ALWAYS Visible
- No `if (folders.isEmpty)` check hides them
- No `if (!_showFolders)` condition
- Comment explicitly states they're shown even before folders load

### Conditions That DO Affect the UI:
1. **Search Expanded** (line 1926)
   - If `_isSearchExpanded == true` → shows search results instead of folder pages
   - Folder tabs still rendered but content changes

2. **Showing Contacts** (line 1931)
   - If `_isShowingContacts == true` → shows contacts panel
   - Folder tabs still rendered but content hidden

3. **Archive Banner** (lines 1932-1944)
   - Shows above folder pages if in "All Chats" tab and archives exist
   - Controlled by `_archiveBannerDismissed`

---

## 7. State Variables Related to Folders

```dart
List<ChatFolder> _folders = [];                    // Line 115
String? _selectedFolderId;                        // Line 116
late TabController _folderTabController;          // Line 117
bool _isShowingContacts = false;                  // Line 143
bool _isInArchive = false;                        // Line 141
```

---

## 8. Key Methods for Folder Management

| Method | Line | Purpose |
|--------|------|---------|
| `_loadFolders()` | 1081 | Loads folders from API response |
| `_updateFolderTabController()` | 1052 | Resizes TabController when folders change |
| `_sortFoldersByOrder()` | 1067 | Orders folders per server |
| `_chatBelongsToFolder()` | 1125 | Filters chats by folder |
| `_filterChats()` | 1201 | Applies folder/search filters |
| `_buildFolderPages()` | (need to find) | Builds content for each folder tab |
| `_onFolderTabChanged()` | (need to find) | Listener for tab changes |

---

## Conclusion

**The folder tabs panel is ALWAYS shown** - there is no conditional hiding. The design shows:
- "All Chats" tab always present
- Additional folder tabs added dynamically
- Panel height: 48px
- Never hidden, only the content changes based on search/contacts mode

If you need to add a condition to hide folder tabs, you would need to:
1. Add a boolean flag (e.g., `bool _hideFolderTabs = false`)
2. Wrap the folder tabs rendering in a conditional
3. Or modify the `ChatsScreenScaffold` to accept a `showFolderTabs` parameter
