import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ad_block_service.dart';

class BrowserTab {
  final String id;
  String url;
  String title;
  InAppWebViewController? controller;
  bool isLoading;
  double progress;
  int blockedAdsCount;
  Uint8List? screenshot;
  bool canGoBack;
  bool canGoForward;
  
  BrowserTab({
    required this.id,
    required this.url,
    this.title = 'Новая вкладка',
    this.controller,
    this.isLoading = true,
    this.progress = 0,
    this.blockedAdsCount = 0,
    this.screenshot,
    this.canGoBack = false,
    this.canGoForward = false,
  });
}

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;

  const BrowserScreen({super.key, this.initialUrl});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();
  
  final List<BrowserTab> _tabs = [];
  int _currentTabIndex = 0;
  bool _showTabBar = false;
  
  late AnimationController _tabsAnimationController;
  late Animation<Offset> _tabsSlideAnimation;
  late Animation<double> _tabsFadeAnimation;

  bool _showBottomBar = true;
  bool _isEditingUrl = false;
  int _lastScrollY = 0;
  Timer? _scrollDebounceTimer;
  bool _isBottomBarAnimating = false;

  static const String _defaultUrl = 'https://duckduckgo.com';
  static const String _defaultSearchEngine = 'https://duckduckgo.com/?q=';
  
  BrowserTab get _currentTab => _tabs[_currentTabIndex];
  InAppWebViewController? get _webViewController => _currentTab.controller;
  String get _currentUrl => _currentTab.url;
  bool get _isLoading => _currentTab.isLoading;
  double get _progress => _currentTab.progress;
  int get _blockedAdsCount => _currentTab.blockedAdsCount;
  bool get _canGoBack => _currentTab.canGoBack;
  bool get _canGoForward => _currentTab.canGoForward;

  @override
  void initState() {
    super.initState();
    
    _tabsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    
    final slideCurve = CurvedAnimation(
      parent: _tabsAnimationController,
      curve: Curves.easeOutQuart,
      reverseCurve: Curves.easeInQuart, 
    );
    
    _tabsSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(slideCurve);
    
    _tabsFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tabsAnimationController,
      curve: Curves.easeOutQuart,
    ));
    
    final initialUrl = widget.initialUrl ?? _defaultUrl;
    _tabs.add(BrowserTab(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: initialUrl,
    ));
    
    _urlController.text = initialUrl;
    _initAdBlock();

    _urlFocusNode.addListener(() {
      setState(() {
        _isEditingUrl = _urlFocusNode.hasFocus;
        if (_isEditingUrl) {
          _urlController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _urlController.text.length,
          );
        }
      });
    });
  }

  Future<void> _initAdBlock() async {
    await AdBlockService.instance.init();
    if (mounted) setState(() {});
  }
  
  Future<void> _captureTabScreenshot(BrowserTab tab) async {
    if (tab.controller == null) return;
    try {
      final screenshot = await tab.controller!.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.JPEG,
          quality: 50,
        ),
      );
      if (screenshot != null && mounted) {
        setState(() {
          tab.screenshot = screenshot;
        });
      }
    } catch (e) {
    }
  }
  
  Future<void> _showTabsPanel() async {
    setState(() {
      _showTabBar = true;
    });
    _tabsAnimationController.forward();
    _captureTabScreenshot(_currentTab);
  }
  
  Future<void> _hideTabsPanel() async {
    await _tabsAnimationController.reverse();
    if (mounted) {
      setState(() {
        _showTabBar = false;
      });
    }
  }
  
  void _createNewTab({String? url}) {
    setState(() {
      _tabs.add(BrowserTab(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        url: url ?? _defaultUrl,
      ));
      _currentTabIndex = _tabs.length - 1;
      _urlController.text = _currentTab.url;
    });
    _hideTabsPanel();
  }
  
  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      Navigator.of(context).pop();
      return;
    }
    
    setState(() {
      _tabs.removeAt(index);
      if (_currentTabIndex >= _tabs.length) {
        _currentTabIndex = _tabs.length - 1;
      }
      _urlController.text = _currentTab.url;
    });
  }
  
  void _switchTab(int index) {
    if (index == _currentTabIndex) {
      _hideTabsPanel();
      return;
    }
    
    setState(() {
      _currentTabIndex = index;
      _urlController.text = _currentTab.url;
    });
    _hideTabsPanel();
  }

  @override
  void dispose() {
    _tabsAnimationController.dispose();
    _scrollDebounceTimer?.cancel();
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  String _formatUrl(String input) {
    input = input.trim();
    if (input.isEmpty) return _defaultUrl;

    if (!input.contains('.') || input.contains(' ')) {
      return '$_defaultSearchEngine${Uri.encodeComponent(input)}';
    }

    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      return 'https://$input';
    }

    return input;
  }

  Future<void> _loadUrl(String url) async {
    final formattedUrl = _formatUrl(url);
    _urlFocusNode.unfocus();
    
    setState(() {
      _currentTab.url = formattedUrl;
    });
    
    try {
      await _webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(formattedUrl)),
      );
    } catch (e) {
    }
  }

  Future<void> _updateNavigationState() async {
    final tab = _currentTab;
    final controller = tab.controller;
    if (controller == null) return;
    
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (mounted) {
        setState(() {
          tab.canGoBack = canGoBack;
          tab.canGoForward = canGoForward;
        });
      }
    } catch (e) {
    }
  }

  void _setBottomBarVisible(bool visible) {
    if (_showBottomBar == visible || _isBottomBarAnimating) return;
    
    _isBottomBarAnimating = true;
    setState(() {
      _showBottomBar = visible;
    });
    
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _isBottomBarAnimating = false;
      }
    });
  }

  String _getDisplayUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (e) {
      return url;
    }
  }

  void _showMoreMenu(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _buildMenuItem(
              icon: Icons.refresh_rounded,
              label: 'Обновить',
              onTap: () {
                Navigator.pop(context);
                try {
                  _webViewController?.reload();
                } catch (e) {
                }
              },
              colors: colors,
            ),
            _buildMenuItem(
              icon: Icons.copy_rounded,
              label: 'Копировать ссылку',
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: _currentUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Скопировано'),
                    backgroundColor: colors.inverseSurface,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.all(16),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              colors: colors,
            ),
            _buildMenuItem(
              icon: Icons.share_rounded,
              label: 'Поделиться',
              onTap: () {
                Navigator.pop(context);
                Share.share(_currentUrl);
              },
              colors: colors,
            ),
            _buildMenuItem(
              icon: Icons.open_in_browser_rounded,
              label: 'Открыть в браузере',
              onTap: () async {
                Navigator.pop(context);
                final uri = Uri.parse(_currentUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              colors: colors,
            ),
            const Divider(height: 1),
            _buildMenuItem(
              icon: Icons.shield_rounded,
              label: 'Блокировщик рекламы',
              subtitle: _blockedAdsCount > 0 
                  ? 'Заблокировано: $_blockedAdsCount'
                  : AdBlockService.instance.isEnabled 
                      ? '${AdBlockService.instance.blockedDomainsCount} доменов'
                      : 'Выключен',
              onTap: () {
                Navigator.pop(context);
                _showAdBlockSettings(context);
              },
              colors: colors,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme colors,
    String? subtitle,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.onSurface),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      color: colors.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTabsPanel(ColorScheme colors, double bottomPadding) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'Вкладки (${_tabs.length})',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _hideTabsPanel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomPadding),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.7,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _tabs.length + 1,
              itemBuilder: (context, index) {
                if (index == _tabs.length) {
                  return _buildAddTabCard(colors);
                }
                
                final tab = _tabs[index];
                final isActive = index == _currentTabIndex;
                
                return _buildTabCard(tab, index, isActive, colors);
              },
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAddTabCard(ColorScheme colors) {
    return GestureDetector(
      onTap: () => _createNewTab(),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: colors.outlineVariant,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_rounded,
                size: 32,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Новая вкладка',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTabCard(BrowserTab tab, int index, bool isActive, ColorScheme colors) {
    return GestureDetector(
      onTap: () => _switchTab(index),
      child: Container(
        decoration: BoxDecoration(
          color: isActive 
              ? colors.primaryContainer 
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: isActive
              ? Border.all(color: colors.primary, width: 2.5)
              : Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isActive ? 13.5 : 15),
          child: Stack(
            children: [
              Positioned.fill(
                child: tab.screenshot != null
                    ? Image.memory(
                        tab.screenshot!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        gaplessPlayback: true,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.surfaceContainerHighest,
                              colors.surfaceContainerLow,
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.language_rounded,
                            size: 48,
                            color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        (isActive ? colors.primaryContainer : colors.surfaceContainerHighest).withValues(alpha: 0.9),
                        isActive ? colors.primaryContainer : colors.surfaceContainerHighest,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (tab.isLoading)
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isActive ? colors.onPrimaryContainer : colors.primary,
                                ),
                              ),
                            )
                          else
                            Icon(
                              tab.url.startsWith('https://')
                                  ? Icons.lock_rounded
                                  : Icons.language_rounded,
                              size: 12,
                              color: isActive ? colors.onPrimaryContainer : colors.primary,
                            ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tab.title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isActive 
                                    ? colors.onPrimaryContainer 
                                    : colors.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getDisplayUrl(tab.url),
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive
                              ? colors.onPrimaryContainer.withValues(alpha: 0.7)
                              : colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () => _closeTab(index),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ),
              if (isActive)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Активная',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdBlockSettings(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          margin: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.shield_rounded, color: colors.primary),
                    const SizedBox(width: 12),
                    const Text(
                      'Блокировщик рекламы',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: AdBlockService.instance.isEnabled,
                      onChanged: (value) async {
                        await AdBlockService.instance.setEnabled(value);
                        setModalState(() {});
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Заблокировано доменов: ${AdBlockService.instance.blockedDomainsCount}',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (_blockedAdsCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'На странице: $_blockedAdsCount',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Свои домены',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (AdBlockService.instance.customDomainsCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${AdBlockService.instance.customDomainsCount}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _showAddCustomDomainDialog(context, setModalState),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
              ),
              if (AdBlockService.instance.customDomains.isNotEmpty)
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: AdBlockService.instance.customDomains.length,
                    itemBuilder: (context, index) {
                      final domain = AdBlockService.instance.customDomains[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          label: Text(domain, style: const TextStyle(fontSize: 12)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () async {
                            await AdBlockService.instance.removeCustomDomain(domain);
                            setModalState(() {});
                            setState(() {});
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    },
                  ),
                ),
              
              const Divider(height: 24),
              
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Hosts-файлы',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.any,
                          allowMultiple: true,
                        );
                        if (result != null) {
                          for (final file in result.files) {
                            if (file.path != null) {
                              await AdBlockService.instance.addHostsFile(file.path!);
                            }
                          }
                          setModalState(() {});
                          setState(() {});
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: AdBlockService.instance.hostsFilePaths.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 48,
                              color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Нет загруженных hosts-файлов',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Нажмите "Добавить" чтобы выбрать файл',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: AdBlockService.instance.hostsFilePaths.length,
                        itemBuilder: (context, index) {
                          final path = AdBlockService.instance.hostsFilePaths[index];
                          final fileName = AdBlockService.instance.getFileName(path);
                          return ListTile(
                            leading: Icon(
                              Icons.description_rounded,
                              color: colors.primary,
                            ),
                            title: Text(
                              fileName,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              path,
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, color: colors.error),
                              onPressed: () async {
                                await AdBlockService.instance.removeHostsFile(path);
                                setModalState(() {});
                                setState(() {});
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCustomDomainDialog(BuildContext context, StateSetter setModalState) {
    final controller = TextEditingController();
    final colors = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить домен'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'example.com',
            helperText: 'Введите домен для блокировки',
            prefixIcon: const Icon(Icons.block),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          keyboardType: TextInputType.url,
          onSubmitted: (value) async {
            if (value.isNotEmpty) {
              final success = await AdBlockService.instance.addCustomDomain(value);
              if (context.mounted) {
                Navigator.pop(context);
                if (success) {
                  setModalState(() {});
                  setState(() {});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Домен уже добавлен или некорректен'),
                      backgroundColor: colors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final success = await AdBlockService.instance.addCustomDomain(controller.text);
                if (context.mounted) {
                  Navigator.pop(context);
                  if (success) {
                    setModalState(() {});
                    setState(() {});
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Домен уже добавлен или некорректен'),
                        backgroundColor: colors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 50;
    
    const topBarContentHeight = 4.0 + 38.0 + 8.0;
    final topBarHeight = topPadding + topBarContentHeight;
    
    final shouldShowBottomBar = _showBottomBar && !isKeyboardOpen;
    
    return Scaffold(
      backgroundColor: colors.surface,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned(
            top: topBarHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: Platform.isLinux
                ? _buildLinuxFallback(colors)
                : GestureDetector(
                    onTap: () {
                      if (_isEditingUrl) {
                        _urlFocusNode.unfocus();
                      }
                    },
                    child: IndexedStack(
                      index: _currentTabIndex,
                      children: _tabs.map((tab) => _buildWebView(colors, tab)).toList(),
                    ),
                  ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
              ),
              child: Padding(
                padding: EdgeInsets.only(top: topPadding),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: _isEditingUrl
                            ? const SizedBox.shrink()
                            : Row(
                                children: [
                                  _buildCircleButton(
                                    icon: Icons.close_rounded,
                                    onTap: () => Navigator.of(context).pop(),
                                    colors: colors,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                              ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (!_isEditingUrl) {
                              setState(() {
                                _isEditingUrl = true;
                              });
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _urlFocusNode.requestFocus();
                              });
                            } else {
                              _urlFocusNode.requestFocus();
                            }
                          },
                          child: Container(
                            height: 38,
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(19),
                            ),
                            child: Row(
                              children: [
                                if (_isEditingUrl)
                                  GestureDetector(
                                    onTap: () {
                                      _urlFocusNode.unfocus();
                                      _urlController.text = _currentUrl;
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 2),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        child: Icon(
                                          Icons.arrow_back_rounded,
                                          size: 18,
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                else ...[
                                  const SizedBox(width: 12),
                                  if (_isLoading)
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          colors.primary,
                                        ),
                                      ),
                                    )
                                  else
                                    Icon(
                                      _currentUrl.startsWith('https://')
                                          ? Icons.lock_rounded
                                          : Icons.lock_open_rounded,
                                      size: 12,
                                      color:
                                          _currentUrl.startsWith('https://')
                                              ? colors.primary
                                              : colors.error,
                                    ),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: _isEditingUrl
                                      ? TextField(
                                          controller: _urlController,
                                          focusNode: _urlFocusNode,
                                          decoration: const InputDecoration(
                                            hintText: 'Поиск или адрес',
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              vertical: 9,
                                            ),
                                          ),
                                          style: TextStyle(
                                            color: colors.onSurface,
                                            fontSize: 13,
                                          ),
                                          keyboardType: TextInputType.url,
                                          textInputAction: TextInputAction.go,
                                          onSubmitted: _loadUrl,
                                        )
                                      : Text(
                                          _getDisplayUrl(_currentUrl),
                                          style: TextStyle(
                                            color: colors.onSurface,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                                if (_isEditingUrl &&
                                    _urlController.text.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => _urlController.clear(),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.clear_rounded,
                                        size: 16,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(width: 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: _isEditingUrl
                            ? const SizedBox.shrink()
                            : Row(
                                children: [
                                  const SizedBox(width: 6),
                                  _buildTabsButton(colors),
                                  const SizedBox(width: 6),
                                  _buildCircleButton(
                                    icon: Icons.more_horiz_rounded,
                                    onTap: () => _showMoreMenu(context),
                                    colors: colors,
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_isLoading && _progress > 0)
            Positioned(
              top: topPadding + 42,
              left: 24,
              right: 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: colors.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  minHeight: 2,
                ),
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !shouldShowBottomBar,
              child: AnimatedOpacity(
                opacity: shouldShowBottomBar ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: AnimatedSlide(
                  offset: Offset(0, shouldShowBottomBar ? 0 : 0.3),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutQuart,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          colors.surface,
                          colors.surface.withValues(alpha: 0.95),
                          colors.surface.withValues(alpha: 0.8),
                          colors.surface.withValues(alpha: 0),
                        ],
                        stops: const [0.0, 0.4, 0.7, 1.0],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildNavButton(
                              icon: Icons.arrow_back_ios_rounded,
                              onTap: _canGoBack
                                  ? () async {
                                      try {
                                        await _webViewController?.goBack();
                                        await _updateNavigationState();
                                      } catch (e) {
                                      }
                                    }
                                  : null,
                              colors: colors,
                            ),
                            _buildNavButton(
                              icon: Icons.arrow_forward_ios_rounded,
                              onTap: _canGoForward
                                  ? () async {
                                      try {
                                        await _webViewController?.goForward();
                                        await _updateNavigationState();
                                      } catch (e) {
                                      }
                                    }
                                  : null,
                              colors: colors,
                            ),
                            _buildNavButton(
                              icon: Icons.home_rounded,
                              onTap: () => _loadUrl(_defaultUrl),
                              colors: colors,
                            ),
                            _buildNavButton(
                              icon: _isLoading
                                  ? Icons.close_rounded
                                  : Icons.refresh_rounded,
                              onTap: () {
                                try {
                                  if (_isLoading) {
                                    _webViewController?.stopLoading();
                                  } else {
                                    _webViewController?.reload();
                                  }
                                } catch (e) {
                                }
                              },
                              colors: colors,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (!_showBottomBar && !isKeyboardOpen && !Platform.isLinux)
            Positioned(
              bottom: bottomPadding + 16,
              right: 16,
              child: GestureDetector(
                onTap: () => _setBottomBarVisible(true),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.expand_less_rounded,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            
          if (_showTabBar)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_showTabBar,
                child: RepaintBoundary(
                  child: FadeTransition(
                    opacity: _tabsFadeAnimation,
                    child: GestureDetector(
                      onTap: _hideTabsPanel,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_showTabBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.85,
              child: IgnorePointer(
                ignoring: !_showTabBar,
                child: RepaintBoundary(
                  child: SlideTransition(
                    position: _tabsSlideAnimation,
                    child: _buildTabsPanel(colors, bottomPadding),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colors,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: colors.onSurface),
      ),
    );
  }
  
  Widget _buildTabsButton(ColorScheme colors) {
    return GestureDetector(
      onTap: _showTabsPanel,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: _tabs.length > 1 
              ? Border.all(color: colors.primary, width: 1.5)
              : null,
        ),
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.tab_rounded,
                size: 18,
                color: colors.onSurface,
              ),
              if (_tabs.length > 1)
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _tabs.length > 99 ? '99+' : '${_tabs.length}',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: colors.onPrimary,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required VoidCallback? onTap,
    required ColorScheme colors,
  }) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 22,
          color: isEnabled
              ? colors.onSurface
              : colors.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildWebView(ColorScheme colors, BrowserTab tab) {
    return InAppWebView(
      key: ValueKey(tab.id),
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: false,
        useOnDownloadStart: true,
        cacheEnabled: true,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        supportZoom: true,
        disableVerticalScroll: false,
        disableHorizontalScroll: false,
        allowsInlineMediaPlayback: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsBackForwardNavigationGestures: true,
        useHybridComposition: true,
        supportMultipleWindows: false,
        javaScriptCanOpenWindowsAutomatically: false,
        databaseEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
      ),
      onWebViewCreated: (controller) {
        setState(() {
          tab.controller = controller;
        });
      },
      onLoadStart: (controller, url) {
        setState(() {
          tab.isLoading = true;
          tab.progress = 0;
          tab.blockedAdsCount = 0;
          if (url != null) {
            tab.url = url.toString();
            if (tab == _currentTab && !_urlFocusNode.hasFocus) {
              _urlController.text = tab.url;
            }
          }
        });
      },
      onLoadStop: (controller, url) async {
        String? title;
        try {
          title = await controller.getTitle();
        } catch (e) {
        }
        
        if (!mounted) return;
        
        setState(() {
          tab.isLoading = false;
          tab.progress = 1;
          if (url != null) {
            tab.url = url.toString();
            if (tab == _currentTab && !_urlFocusNode.hasFocus) {
              _urlController.text = tab.url;
            }
          }
          if (title != null && title.isNotEmpty) {
            tab.title = title;
          }
        });
        
        if (tab == _currentTab) {
          await _updateNavigationState();
        }
        
        await _captureTabScreenshot(tab);
      },
      onProgressChanged: (controller, progress) {
        setState(() {
          tab.progress = progress / 100;
        });
      },
      onScrollChanged: (controller, x, y) {
        if (tab != _currentTab) return;
        
        final scrollDelta = y - _lastScrollY;
        _lastScrollY = y;
        
        bool? targetVisible;
        if (scrollDelta > 15 && _showBottomBar && y > 100) {
          targetVisible = false;
        } else if (scrollDelta < -15 && !_showBottomBar) {
          targetVisible = true;
        }
        
        if (targetVisible != null) {
          _scrollDebounceTimer?.cancel();
          _scrollDebounceTimer = Timer(const Duration(milliseconds: 50), () {
            _setBottomBarVisible(targetVisible!);
          });
        }
      },
      onUpdateVisitedHistory: (controller, url, androidIsReload) async {
        if (!mounted) return;
        
        if (url != null) {
          setState(() {
            tab.url = url.toString();
            if (tab == _currentTab && !_urlFocusNode.hasFocus) {
              _urlController.text = tab.url;
            }
          });
        }
        
        if (tab == _currentTab) {
          await _updateNavigationState();
        }
        
        try {
          final canGoBack = await controller.canGoBack();
          final canGoForward = await controller.canGoForward();
          if (mounted) {
            setState(() {
              tab.canGoBack = canGoBack;
              tab.canGoForward = canGoForward;
            });
          }
        } catch (e) {
        }
      },
      onReceivedError: (controller, request, error) {
        print('❌ Browser error: ${error.description} (${error.type})');
      },
      onDownloadStartRequest: (controller, downloadStartRequest) async {
        final url = downloadStartRequest.url.toString();
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      onCreateWindow: (controller, createWindowAction) async {
        final uri = createWindowAction.request.url;
        if (uri != null) {
          _createNewTab(url: uri.toString());
        }
        return true;
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        if (uri != null) {
          final scheme = uri.scheme;
          if (scheme != 'http' && scheme != 'https') {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationActionPolicy.CANCEL;
            }
          }
          if (AdBlockService.instance.shouldBlockDomain(uri.toString())) {
            setState(() {
              tab.blockedAdsCount++;
            });
            return NavigationActionPolicy.CANCEL;
          }
        }
        return NavigationActionPolicy.ALLOW;
      },
      shouldInterceptRequest: (controller, request) async {
        if (!AdBlockService.instance.isEnabled) return null;
        
        final url = request.url.toString();
        if (AdBlockService.instance.shouldBlockDomain(url)) {
          setState(() {
            tab.blockedAdsCount++;
          });
          return WebResourceResponse(
            contentType: 'text/plain',
            data: Uint8List(0),
          );
        }
        return null;
      },
    );
  }

  Widget _buildLinuxFallback(ColorScheme colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.public_off_rounded,
            size: 64,
            color: colors.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Браузер недоступен на Linux',
            style: TextStyle(
              fontSize: 16,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
