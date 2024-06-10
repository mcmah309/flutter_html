import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/tree/image_element.dart';

class ImageBuiltIn extends HtmlExtension {
  final String? dataEncoding;
  final Set<String>? mimeTypes;
  final Map<String, String>? networkHeaders;
  final Set<String> networkSchemas;
  final Set<String>? networkDomains;
  final Set<String>? fileExtensions;

  final String assetSchema;
  final AssetBundle? assetBundle;
  final String? assetPackage;

  final bool handleNetworkImages;
  final bool handleAssetImages;
  final bool handleDataImages;

  const ImageBuiltIn({
    this.networkHeaders,
    this.networkDomains,
    this.networkSchemas = const {"http", "https"},
    this.fileExtensions,
    this.assetSchema = "asset:",
    this.assetBundle,
    this.assetPackage,
    this.mimeTypes,
    this.dataEncoding,
    this.handleNetworkImages = true,
    this.handleAssetImages = true,
    this.handleDataImages = true,
  });

  @override
  Set<String> get supportedTags => {
        "img",
      };

  @override
  bool matches(ExtensionContext context) {
    if (context.elementName != "img") {
      return false;
    }

    return (_matchesNetworkImage(context) && handleNetworkImages) ||
        (_matchesAssetImage(context) && handleAssetImages) ||
        (_matchesBase64Image(context) && handleDataImages);
  }

  @override
  StyledElement prepare(ExtensionContext context, List<StyledElement> children) {
    final parsedWidth = double.tryParse(context.attributes["width"] ?? "");
    final parsedHeight = double.tryParse(context.attributes["height"] ?? "");

    Width? width = parsedWidth != null ? Width(parsedWidth) : null;
    Height? height = parsedHeight != null ? Height(parsedHeight) : null;
    return ImageElement(
      name: context.elementName,
      children: children,
      style: Style(width: width, height: height),
      node: context.node,
      elementId: context.id,
      src: context.attributes["src"]!,
      alt: context.attributes["alt"],
      width: width,
      height: height,
    );
  }

  @override
  InlineSpan build(ExtensionContext context, MarkManager markManager) {
    final element = context.styledElement as ImageElement;

    // final imageStyle = Style(
    //   width: element.width,
    //   height: element.height,
    // ).merge(context.styledElement!.style);

    late Widget child;
    if (_matchesBase64Image(context)) {
      child = _base64ImageRender(context, element);
    } else if (_matchesAssetImage(context)) {
      child = _assetImageRender(context, element);
    } else if (_matchesNetworkImage(context)) {
      child = _networkImageRender(context, element, markManager);
    } else {
      // Our matcher went a little overboard and matched
      // something we can't render
      return TextSpan(text: element.alt);
    }

    return WidgetSpan(
      child: CssBoxWidget(
        styledElement: context.styledElement!,
        childIsReplaced: true,
        markManager: markManager,
        child: child,
      ),
    );
  }

  static RegExp get dataUriFormat =>
      RegExp(r"^(?<scheme>data):(?<mime>image/[\w+\-.]+);*(?<encoding>base64)?,\s*(?<data>.*)");

  bool _matchesBase64Image(ExtensionContext context) {
    final attributes = context.attributes;

    if (attributes['src'] == null) {
      return false;
    }

    final dataUri = dataUriFormat.firstMatch(attributes['src']!);

    return context.elementName == "img" &&
        dataUri != null &&
        (mimeTypes == null || mimeTypes!.contains(dataUri.namedGroup('mime'))) &&
        dataUri.namedGroup('mime') != 'image/svg+xml' &&
        (dataEncoding == null || dataUri.namedGroup('encoding') == dataEncoding);
  }

  bool _matchesAssetImage(ExtensionContext context) {
    final attributes = context.attributes;

    return context.elementName == "img" &&
        attributes['src'] != null &&
        !attributes['src']!.endsWith(".svg") &&
        attributes['src']!.startsWith(assetSchema) &&
        (fileExtensions == null || attributes['src']!.endsWithAnyFileExtension(fileExtensions!));
  }

  bool _matchesNetworkImage(ExtensionContext context) {
    final attributes = context.attributes;

    if (attributes['src'] == null) {
      return false;
    }

    final src = Uri.tryParse(attributes['src']!);
    if (src == null) {
      return false;
    }

    return context.elementName == "img" &&
        networkSchemas.contains(src.scheme) &&
        !src.path.endsWith(".svg") &&
        (networkDomains == null || networkDomains!.contains(src.host)) &&
        (fileExtensions == null || src.path.endsWithAnyFileExtension(fileExtensions!));
  }

  Widget _base64ImageRender(ExtensionContext context, StyledElement element) {
    final element = context.styledElement as ImageElement;
    final decodedImage = base64.decode(element.src.split("base64,")[1].trim());

    return Image.memory(
      decodedImage,
      width: element.style.width?.value,
      height: element.style.height?.value,
      fit: BoxFit.fill,
      errorBuilder: (ctx, error, stackTrace) {
        return Text(
          element.alt ?? "",
          style: context.styledElement!.style.generateTextStyle(),
        );
      },
    );
  }

  Widget _assetImageRender(ExtensionContext context, StyledElement styledElement) {
    final element = context.styledElement as ImageElement;
    final assetPath = element.src.replaceFirst('asset:', '');

    return Image.asset(
      assetPath,
      width: styledElement.style.width?.value,
      height: styledElement.style.height?.value,
      fit: BoxFit.fill,
      bundle: assetBundle,
      package: assetPackage,
      errorBuilder: (ctx, error, stackTrace) {
        return Text(
          element.alt ?? "",
          style: context.styledElement!.style.generateTextStyle(),
        );
      },
    );
  }

  Widget _networkImageRender(
      ExtensionContext context, StyledElement styledElement, MarkManager markManager) {
    final element = context.styledElement as ImageElement;

    return CssBoxWidget(
      styledElement: styledElement,
      markManager: markManager,
      childIsReplaced: true,
      child: Image.network(
        element.src,
        width: styledElement.style.width?.value,
        height: styledElement.style.height?.value,
        fit: BoxFit.fill,
        headers: networkHeaders,
        errorBuilder: (ctx, error, stackTrace) {
          return Text(
            element.alt ?? "",
            style: context.styledElement!.style.generateTextStyle(),
          );
        },
      ),
    );
  }
}

extension _SetFolding on String {
  bool endsWithAnyFileExtension(Iterable<String> endings) {
    for (final element in endings) {
      if (endsWith(".$element")) {
        return true;
      }
    }
    return false;
  }
}
