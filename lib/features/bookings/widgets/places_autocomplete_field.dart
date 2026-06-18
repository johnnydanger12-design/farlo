import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _apiKey = String.fromEnvironment('GOOGLE_PLACES_API_KEY');

class PlacesAutocompleteField extends StatefulWidget {
  const PlacesAutocompleteField({
    super.key,
    required this.controller,
    this.validator,
    this.label = '* Event location / address',
    this.onCoordinatesSelected,
  });

  final TextEditingController controller;
  final String? Function(String?)? validator;
  final String label;
  final void Function(double lat, double lng)? onCoordinatesSelected;

  @override
  State<PlacesAutocompleteField> createState() => _PlacesAutocompleteFieldState();
}

class _PlacesAutocompleteFieldState extends State<PlacesAutocompleteField> {
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<_Prediction> _suggestions = [];
  Timer? _debounce;
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _removeOverlay();
  }

  void _onTextChanged() {
    if (_selecting) return;
    _debounce?.cancel();
    final query = widget.controller.text.trim();
    if (query.length < 3) {
      _removeOverlay();
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _fetchSuggestions(query),
    );
  }

  Future<void> _fetchSuggestions(String query) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': query,
      'components': 'country:us',
      'key': _apiKey,
    });
    try {
      final res = await http.get(uri);
      if (!mounted) return;
      final data = json.decode(res.body) as Map<String, dynamic>;
      final preds = (data['predictions'] as List? ?? []).map((p) {
        final fmt = p['structured_formatting'] as Map<String, dynamic>?;
        return _Prediction(
          placeId: p['place_id'] as String,
          description: p['description'] as String,
          mainText: (fmt?['main_text'] as String?) ?? p['description'] as String,
          secondaryText: fmt?['secondary_text'] as String?,
        );
      }).toList();
      _updateSuggestions(preds);
    } catch (_) {
      _removeOverlay();
    }
  }

  Future<void> _selectPrediction(_Prediction pred) async {
    _selecting = true;
    _removeOverlay();

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': pred.placeId,
      'fields': 'formatted_address,geometry',
      'key': _apiKey,
    });
    try {
      final res = await http.get(uri);
      final data = json.decode(res.body) as Map<String, dynamic>;
      final result = data['result'] as Map<String, dynamic>?;
      final address = result?['formatted_address'] as String?;
      final text = address ?? pred.description;
      widget.controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      if (widget.onCoordinatesSelected != null) {
        final loc = (result?['geometry'] as Map<String, dynamic>?)?['location'] as Map<String, dynamic>?;
        if (loc != null) {
          final lat = (loc['lat'] as num).toDouble();
          final lng = (loc['lng'] as num).toDouble();
          widget.onCoordinatesSelected!(lat, lng);
        }
      }
    } catch (_) {
      widget.controller.value = TextEditingValue(
        text: pred.description,
        selection: TextSelection.collapsed(offset: pred.description.length),
      );
    }

    _selecting = false;
    _focusNode.unfocus();
  }

  void _updateSuggestions(List<_Prediction> preds) {
    _suggestions = preds;
    if (preds.isEmpty) {
      _removeOverlay();
    } else if (_overlay == null) {
      _showOverlay();
    } else {
      _overlay!.markNeedsBuild();
    }
  }

  void _showOverlay() {
    _overlay = _buildOverlay();
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
    _suggestions = [];
  }

  OverlayEntry _buildOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final fieldSize = renderBox.size;

    return OverlayEntry(
      builder: (_) {
        final theme = Theme.of(context);
        final isLight = theme.brightness == Brightness.light;
        return Positioned(
          width: fieldSize.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, fieldSize.height + 4),
            child: Material(
              elevation: 6,
              color: isLight ? Colors.white : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant,
                  ),
                  itemBuilder: (_, i) {
                    final pred = _suggestions[i];
                    return InkWell(
                      onTap: () => _selectPrediction(pred),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pred.mainText,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (pred.secondaryText != null) ...[
                                    const SizedBox(height: 1),
                                    Text(
                                      pred.secondaryText!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        validator: widget.validator,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _focusNode.unfocus(),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixIcon: const Icon(Icons.search_outlined, size: 18),
        ),
      ),
    );
  }
}

class _Prediction {
  const _Prediction({
    required this.placeId,
    required this.description,
    required this.mainText,
    this.secondaryText,
  });

  final String placeId;
  final String description;
  final String mainText;
  final String? secondaryText;
}
