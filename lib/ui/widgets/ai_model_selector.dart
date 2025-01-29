import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cool_dropdown/cool_dropdown.dart';
import 'package:cool_dropdown/models/cool_dropdown_item.dart';

class AIModel {
  final String id;
  final String name;
  final String logoUrl;
  final String description;
  final Color accentColor;
  final Map<String, dynamic> config;

  const AIModel({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.description,
    required this.accentColor,
    required this.config,
  });

  CoolDropdownItem<String> toDropdownItem() {
    return CoolDropdownItem<String>(
      label: name,
      value: id,
      icon: ClipOval(
        child: Image.network(
          logoUrl,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.smart_toy_outlined,
              size: 20,
              color: accentColor,
            );
          },
        ),
      ),
    );
  }
}

final availableModelsProvider = Provider<List<AIModel>>((ref) {
  return [
    AIModel(
      id: 'predis',
      name: 'Predis AI',
      logoUrl: 'https://predis.ai/developers/img/predis_logo_Solid.png',
      description: 'Professional video generation',
      accentColor: Colors.blue,
      config: {
        'apiKey': const String.fromEnvironment('PREDIS_API_KEY'),
        'brandId': const String.fromEnvironment('PREDIS_BRAND_ID'),
      },
    ),
    // Add more models here when available
  ];
});

final selectedModelProvider = StateProvider<AIModel?>((ref) {
  final models = ref.watch(availableModelsProvider);
  return models.isNotEmpty ? models.first : null;
});

class AIModelSelector extends ConsumerWidget {
  final Color accentColor;
  final VoidCallback? onModelSelected;

  const AIModelSelector({
    super.key,
    required this.accentColor,
    this.onModelSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(availableModelsProvider);
    final selectedModel = ref.watch(selectedModelProvider);

    if (models.isEmpty || selectedModel == null) {
      return const SizedBox.shrink();
    }

    final dropdownItems = models.map((model) => model.toDropdownItem()).toList();
    final dropdownController = DropdownController<String>();

    return SizedBox(
      height: 40,
      width: 70,
      child: CoolDropdown<String>(
        controller: dropdownController,
        dropdownList: dropdownItems,
        defaultItem: selectedModel.toDropdownItem(),
        onChange: (value) {
          if (value != null) {
            final selectedModel = models.firstWhere((m) => m.id == value);
            ref.read(selectedModelProvider.notifier).state = selectedModel;
            onModelSelected?.call();
            dropdownController.close();
          }
        },
        resultOptions: ResultOptions(
          width: 50,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          boxDecoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor.withAlpha(77),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withAlpha(26),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          openBoxDecoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withAlpha(51),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          render: ResultRender.icon,
          icon: SizedBox(
            width: 10,
            height: 10,
            child: CustomPaint(
              painter: DropdownArrowPainter(color: Colors.grey[400] ?? Colors.grey),
            ),
          ),
        ),
        dropdownOptions: DropdownOptions(
          width: 160,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          gap: DropdownGap.all(5),
          borderSide: BorderSide(
            color: accentColor.withAlpha(77),
            width: 1,
          ),
          animationType: DropdownAnimationType.size,
          align: DropdownAlign.center,
          selectedItemAlign: SelectedItemAlign.center,
        ),
        dropdownItemOptions: DropdownItemOptions(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          mainAxisAlignment: MainAxisAlignment.start,
          render: DropdownItemRender.all,
          textStyle: TextStyle(
            color: Colors.grey[300],
            fontSize: 14,
          ),
          selectedTextStyle: TextStyle(
            color: Colors.grey[300],
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          selectedBoxDecoration: BoxDecoration(
            color: Colors.transparent,
          ),
        ),
        dropdownTriangleOptions: DropdownTriangleOptions(
          width: 20,
          height: 20,
          align: DropdownTriangleAlign.right,
          borderRadius: 4,
        ),
      ),
    );
  }
} 