import 'package:flutter/material.dart';
import 'package:caption_trans/l10n/app_localizations.dart';
import '../../services/settings_service.dart';
import 'pages/single_task_page.dart';
import 'pages/batch_task_page.dart';
import 'pages/alist_task_page.dart';
import 'widgets/settings_dialog.dart';

class MainLayout extends StatefulWidget {
  final SettingsService settingsService;
  final void Function(Locale) onLocaleChanged;

  const MainLayout({
    super.key,
    required this.settingsService,
    required this.onLocaleChanged,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;
  bool _isExtended = true;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _openSettings() {
    final locale = Localizations.localeOf(context);
    showDialog(
      context: context,
      builder: (_) => SettingsDialog(
        currentLocale: locale,
        onLocaleChanged: widget.onLocaleChanged,
        providerCredentials: widget.settingsService.llmProviderCredentials,
        settingsService: widget.settingsService,
        onDeleteProviderCredential: (provider) async {
          await widget.settingsService.deleteLlmProviderCredential(provider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    
    // Auto-collapse sidebar on smaller screens
    final shouldExtend = size.width >= 800;
    if (_isExtended != shouldExtend) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isExtended = shouldExtend);
      });
    }

    final pages = [
      SingleTaskPage(
        settingsService: widget.settingsService,
        onLocaleChanged: widget.onLocaleChanged,
      ),
      BatchTaskPage(settingsService: widget.settingsService),
      AListTaskPage(settingsService: widget.settingsService),
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Custom macOS-style Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _isExtended ? 240 : 72,
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.3),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // Header (Logo)
                Padding(
                  padding: const EdgeInsets.only(top: 32, bottom: 24),
                  child: _isExtended
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.subtitles_rounded,
                              color: theme.colorScheme.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Caption Trans',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        )
                      : Icon(
                          Icons.subtitles_rounded,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                ),
                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _buildNavItem(
                        index: 0,
                        icon: Icons.description_outlined,
                        selectedIcon: Icons.description_rounded,
                        label: '单文件任务',
                        theme: theme,
                      ),
                      const SizedBox(height: 8),
                      _buildNavItem(
                        index: 1,
                        icon: Icons.library_books_outlined,
                        selectedIcon: Icons.library_books_rounded,
                        label: '批量字幕',
                        theme: theme,
                      ),
                      const SizedBox(height: 8),
                      _buildNavItem(
                        index: 2,
                        icon: Icons.library_music_outlined,
                        selectedIcon: Icons.library_music_rounded,
                        label: 'AList 转换',
                        theme: theme,
                      ),
                    ],
                  ),
                ),
                // Footer (Settings)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: IconButton(
                    icon: const Icon(Icons.settings_rounded),
                    onPressed: _openSettings,
                    tooltip: l10n.settings,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main Content Area
          Expanded(
            child: Container(
              color: Colors.transparent,
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_selectedIndex),
                    child: pages[_selectedIndex],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required ThemeData theme,
  }) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: _isExtended ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected
                  ? theme.colorScheme.primary
                  : Colors.white.withValues(alpha: 0.7),
              size: 22,
            ),
            if (_isExtended) ...[
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
