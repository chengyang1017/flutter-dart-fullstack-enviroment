/// Adds presentation translations to the one-time lesson catalog migration
/// payload without changing the executable lesson/checker models.
///
/// The canonical built-in lesson objects stay in Chinese so existing starter
/// code, AST checks and answer assets keep working exactly as before. The
/// remote catalog stores both languages under `translations`, allowing the
/// Jaspr admin console (and future clients) to present polished English copy.
abstract final class LessonCatalogPublishingTranslations {
  static Map<String, Object?> enrich(Map<String, Object?> catalog) {
    catalog['schemaVersion'] = 2;
    catalog['defaultLanguage'] = 'zh';
    catalog['availableLanguages'] = const ['zh', 'en'];

    final projects = catalog['projects'];
    if (projects is! Iterable) return catalog;

    for (final rawProject in projects) {
      if (rawProject is! Map) continue;
      final project = Map<String, Object?>.from(rawProject);
      _replaceMapEntry(rawProject, project);
      final projectId = project['id']?.toString() ?? '';
      final english = _projectEnglish[projectId];
      if (english != null) {
        _attachTranslations(
          project,
          english,
          const ['title', 'description'],
        );
      }

      final lessons = project['lessons'];
      if (lessons is! Iterable) continue;
      for (final rawLesson in lessons) {
        if (rawLesson is! Map) continue;
        final lesson = Map<String, Object?>.from(rawLesson);
        _replaceMapEntry(rawLesson, lesson);
        final lessonId = lesson['id']?.toString() ?? '';
        final lessonEnglish = _lessonEnglish[lessonId];
        if (lessonEnglish != null) {
          _attachTranslations(
            lesson,
            lessonEnglish,
            const [
              'title',
              'description',
              'difficulty',
              'category',
              'tags',
              'prerequisites',
            ],
          );
        }

        final steps = lesson['steps'];
        if (steps is! Iterable) continue;
        for (final rawStep in steps) {
          if (rawStep is! Map) continue;
          final step = Map<String, Object?>.from(rawStep);
          _replaceMapEntry(rawStep, step);
          final stepId = step['id']?.toString() ?? '';
          final stepEnglish = _stepEnglish[stepId];
          if (stepEnglish != null) {
            _attachTranslations(
              step,
              stepEnglish,
              const ['part', 'title', 'instruction', 'explanation', 'hints'],
            );
          }
        }
      }
    }

    return catalog;
  }

  static void _attachTranslations(
    Map<String, Object?> node,
    Map<String, Object?> english,
    List<String> fields,
  ) {
    final chinese = <String, Object?>{};
    for (final field in fields) {
      if (node.containsKey(field)) chinese[field] = node[field];
    }
    node['translations'] = <String, Object?>{
      'zh': chinese,
      'en': english,
    };
  }

  static void _replaceMapEntry(Map raw, Map<String, Object?> normalized) {
    raw
      ..clear()
      ..addAll(normalized);
  }

  static const Map<String, Map<String, Object?>> _projectEnglish = {
    'post-development': {
      'title': 'Social & Post Development',
      'description':
          'Build authentication, publishing, feeds, interactions, direct messaging and user profiles.',
    },
    'shopping-development': {
      'title': 'Commerce Development',
      'description':
          'Build a complete commerce flow covering products, cart, addresses, orders and payments.',
    },
  };

  static const Map<String, Map<String, Object?>> _lessonEnglish = {
    'create-text-post-advanced-images': {
      'title': 'Publish a Text Post',
      'description':
          'Build a posting flow in three layers: composer UI, submit logic and Firebase persistence with image upload.',
      'difficulty': 'Advanced · Images',
      'category': 'Post System',
      'tags': ['UI', 'Logic', 'Firebase', 'Storage'],
      'prerequisites': ['Understand StatefulWidget', 'Understand async/await'],
    },
    'post-list': {
      'title': 'Post Feed',
      'description': 'Display a real-time post feed with loading and empty states.',
      'difficulty': 'Coming soon',
      'category': 'Post System',
      'tags': ['UI', 'Firestore'],
      'prerequisites': ['Publish a Text Post'],
    },
    'post-detail': {
      'title': 'Post Details',
      'description': 'Combine post content, author information and interaction controls.',
      'difficulty': 'Coming soon',
      'category': 'Post System',
      'tags': ['UI', 'Routing'],
      'prerequisites': ['Post Feed'],
    },
    'like-post': {
      'title': 'Likes',
      'description': 'Implement like, unlike and synchronized interaction state.',
      'difficulty': 'Coming soon',
      'category': 'Post System',
      'tags': ['Logic', 'Firebase'],
      'prerequisites': ['Post Feed'],
    },
    'comments': {
      'title': 'Comments',
      'description': 'Create comments, render the comment list and maintain counters.',
      'difficulty': 'Coming soon',
      'category': 'Post System',
      'tags': ['UI', 'Logic', 'Firebase'],
      'prerequisites': ['Post Details'],
    },
    'delete-post': {
      'title': 'Delete Posts',
      'description': 'Add permission checks, confirmation UX and safe deletion.',
      'difficulty': 'Coming soon',
      'category': 'Post System',
      'tags': ['Logic', 'Firebase'],
      'prerequisites': ['Publish a Text Post'],
    },
    'register': {
      'title': 'User Registration',
      'description': 'Build registration UI, validation and Firebase Auth sign-up.',
      'difficulty': 'Coming soon',
      'category': 'User System',
      'tags': ['UI', 'FirebaseAuth'],
      'prerequisites': <String>[],
    },
    'login': {
      'title': 'User Login',
      'description': 'Build login UI, error feedback and session entry.',
      'difficulty': 'Coming soon',
      'category': 'User System',
      'tags': ['UI', 'FirebaseAuth'],
      'prerequisites': ['User Registration'],
    },
    'chat': {
      'title': 'Direct Messaging',
      'description': 'Build conversations, message sending and a real-time message stream.',
      'difficulty': 'Coming soon',
      'category': 'Chat System',
      'tags': ['UI', 'Firestore'],
      'prerequisites': ['User Login'],
    },
    'profile': {
      'title': 'User Profile',
      'description': 'Combine profile data, post statistics and the user’s post list.',
      'difficulty': 'Coming soon',
      'category': 'Profile',
      'tags': ['UI', 'Firestore'],
      'prerequisites': ['Post Feed', 'User Login'],
    },
    'product-home': {
      'title': 'Product Home',
      'description': 'Build the product home title, product information and purchase action step by step.',
      'difficulty': 'Beginner',
      'category': 'Product System',
      'tags': ['UI', 'Column', 'Text', 'Button'],
      'prerequisites': ['Understand StatelessWidget', 'Understand Column and Text'],
    },
    'product-model': {
      'title': 'Product Model',
      'description': 'Define product data structures, fields and conversion logic.',
      'difficulty': 'Coming soon',
      'category': 'Product System',
      'tags': ['Model', 'Dart'],
      'prerequisites': ['Product Home'],
    },
    'product-detail': {
      'title': 'Product Details',
      'description': 'Display product imagery, price, description and purchase actions.',
      'difficulty': 'Coming soon',
      'category': 'Product System',
      'tags': ['UI', 'Routing'],
      'prerequisites': ['Product Model'],
    },
    'shopping-cart-complete': {
      'title': 'Production Shopping Cart',
      'description':
          'Rebuild the shoppingapp123 cart architecture end to end: models, local persistence, repository, Provider, UI, app entry points, dependency injection and checkout integration.',
      'difficulty': 'Advanced · Full Project',
      'category': 'Shopping Cart',
      'tags': ['Model', 'SharedPreferences', 'Repository', 'Provider', 'UI', 'Integration'],
      'prerequisites': [
        'Understand Dart classes and factory constructors',
        'Understand async/await',
        'Understand ChangeNotifier and Provider',
        'Understand Service / Repository layering',
      ],
    },
    'shipping-address': {
      'title': 'Shipping Address',
      'description': 'Build the address model, address list and address selection flow.',
      'difficulty': 'Coming soon',
      'category': 'Address System',
      'tags': ['UI', 'Repository'],
      'prerequisites': ['Shopping Cart'],
    },
    'checkout': {
      'title': 'Checkout',
      'description': 'Combine cart totals, shipping address and payment method.',
      'difficulty': 'Coming soon',
      'category': 'Order System',
      'tags': ['UI', 'Provider'],
      'prerequisites': ['Shopping Cart', 'Shipping Address'],
    },
    'create-order': {
      'title': 'Create an Order',
      'description': 'Convert the current cart into a persisted order.',
      'difficulty': 'Coming soon',
      'category': 'Order System',
      'tags': ['Logic', 'Repository'],
      'prerequisites': ['Checkout'],
    },
    'order-list': {
      'title': 'Order List',
      'description': 'Display user orders, status and creation time.',
      'difficulty': 'Coming soon',
      'category': 'Order System',
      'tags': ['UI', 'Firestore'],
      'prerequisites': ['Create an Order'],
    },
    'order-detail': {
      'title': 'Order Details',
      'description': 'Display ordered products, shipping address, totals and payment status.',
      'difficulty': 'Coming soon',
      'category': 'Order System',
      'tags': ['UI', 'Routing'],
      'prerequisites': ['Order List'],
    },
    'stripe-payment': {
      'title': 'Stripe Payment',
      'description': 'Create a Stripe payment flow and update order state from the result.',
      'difficulty': 'Coming soon',
      'category': 'Payment System',
      'tags': ['Stripe', 'Firebase'],
      'prerequisites': ['Order Details'],
    },
  };

  static const Map<String, Map<String, Object?>> _stepEnglish = {
    'create-post-part-1': {
      'part': 'Part 1: Post Composer UI',
      'title': 'Form Inputs',
      'instruction': 'Build the TextEditingController, TextField and publish-button input area.',
      'explanation':
          'This section focuses only on runnable declarative UI. The author solution for CreatePostPage has not been attached yet.',
      'hints': ['Build the visible input and button structure first, then run the current code.'],
    },
    'create-post-part-2': {
      'part': 'Part 2: Publish Button Logic',
      'title': 'Submit Logic',
      'instruction':
          'Implement _publishPost, trim input, validate content, prevent duplicate submissions and handle mounted safely.',
      'explanation':
          'Validation uses the Dart AST and does not execute the code. The author solution for _publishPost has not been attached yet.',
      'hints': ['Implement trim, empty-content checks, submission state and the service call separately.'],
    },
    'create-post-part-3': {
      'part': 'Part 3: Firebase Persistence',
      'title': 'Firebase Persistence',
      'instruction':
          'Implement PostService.createPost with multi-image upload, failure cleanup and author-profile lookup.',
      'explanation':
          'This is the advancedImages section. The author PostService source is not attached yet, so the answer repository will show it as unavailable.',
      'hints': ['Check the flow in four stages: Auth, Storage upload, Firestore write and rollback on failure.'],
    },
    'product-home-step-1': {
      'part': 'Part 1: Product Home Skeleton',
      'title': 'Build Product Home',
      'instruction': 'Use a Column to build the product name, price and purchase button.',
      'explanation':
          'Practice the most basic declarative commerce UI. The page should contain a Column, product name, product price and purchase button.',
      'hints': [
        'Use Column as the outermost widget.',
        'Use Text for the product name and price.',
        'Use ElevatedButton for the purchase action.',
      ],
    },
    'shopping-cart-part-01-product-model': {
      'part': 'Part 1: Product Model',
      'title': 'Build Product',
      'instruction': 'Recreate the original Product fields, JSON conversion and sample product data.',
      'explanation': 'The cart persists complete Product values, so Product must support toJson and fromJson first.',
      'hints': [
        'Include id, categoryId, title, image, price and sold.',
        'Convert price to double when reading JSON.',
        'Convert sold to int when reading JSON.',
      ],
    },
    'shopping-cart-part-02-cart-item': {
      'part': 'Part 2: Cart Item Model',
      'title': 'Build CartItem',
      'instruction': 'Model the product, quantity, subtotal, copyWith and JSON conversion from the original project.',
      'explanation': 'CartItem combines Product and quantity into a persistable cart entry.',
      'hints': [
        'subtotal is product price multiplied by quantity.',
        'Use copyWith when increasing or decreasing quantity.',
        'toJson should continue to call product.toJson().',
      ],
    },
    'shopping-cart-part-03-cart-service': {
      'part': 'Part 3: Local Cart Service',
      'title': 'Persist Cart with SharedPreferences',
      'instruction': 'Implement CartService and LocalCartService with load, save, clear and corrupted-data recovery.',
      'explanation': 'The service serializes the cart to local JSON and does not own UI state.',
      'hints': [
        'Use SharedPreferencesAsync.',
        'Call jsonEncode before saving.',
        'Use jsonDecode and CartItem.fromJson when loading.',
        'Remove corrupted data and return an empty list.',
      ],
    },
    'shopping-cart-part-04-cart-repository': {
      'part': 'Part 4: Cart Repository',
      'title': 'Isolate the Data Source',
      'instruction': 'Build CartRepository to separate Provider from CartService.',
      'explanation': 'The repository exposes cart semantics upward and delegates storage to the concrete service.',
      'hints': [
        'Inject CartService through the constructor.',
        'loadCart delegates to loadItems.',
        'saveCart delegates to saveItems.',
        'clearCart delegates to clear.',
      ],
    },
    'shopping-cart-part-05-cart-provider': {
      'part': 'Part 5: Cart State Management',
      'title': 'Implement CartProvider',
      'instruction':
          'Implement loading, totals, add/increase/decrease/remove/clear, operation queuing, optimistic updates and rollback.',
      'explanation':
          'This is the cart core. The operation queue prevents rapid actions from overwriting state; optimistic updates change the UI immediately and roll back if persistence fails.',
      'hints': [
        'Expose the list through UnmodifiableListView.',
        'Route all writes through _enqueue.',
        '_saveOptimistically updates UI first and restores previousItems on failure.',
        'Remove an item when quantity would fall below 1.',
      ],
    },
    'shopping-cart-part-06-cart-item-tile': {
      'part': 'Part 6: Cart Item Tile',
      'title': 'Build CartItemTile',
      'instruction': 'Implement product image, title, unit price, subtotal, quantity controls and delete action.',
      'explanation': 'CartItemTile is presentation-only and delegates operations back to CartPage through callbacks.',
      'hints': [
        'Do not read Provider directly inside the tile.',
        'Inject increase, decrease and remove as VoidCallbacks.',
        'Show a placeholder icon if the image fails to load.',
      ],
    },
    'shopping-cart-part-07-cart-page': {
      'part': 'Part 7: Cart Page',
      'title': 'Implement CartPage',
      'instruction':
          'Build loading, error and empty states, item list, quantity updates, removal, clear, totals, checkout entry and error feedback.',
      'explanation': 'CartPage combines every CartProvider state and operation into a complete cart experience.',
      'hints': [
        'Use context.watch for page state.',
        'Render each item with CartItemTile.',
        'Show an AlertDialog before clearing.',
        'Route operation failures through _runCartAction.',
      ],
    },
    'shopping-cart-part-08-cart-icon': {
      'part': 'Part 8: Cart Quantity Badge',
      'title': 'Build CartIconButton',
      'instruction': 'Implement the cart entry, Selector-based partial listening, quantity badge and 99+ cap.',
      'explanation': 'Selector listens only to totalQuantity so unrelated cart state does not rebuild the whole button.',
      'hints': [
        'The Selector result type is int.',
        'Hide the badge when quantity is 0.',
        'Open CartPage when tapped.',
      ],
    },
    'shopping-cart-part-09-product-details': {
      'part': 'Part 9: Add from Product Details',
      'title': 'Add to Cart and Buy Now',
      'instruction': 'Implement quantity display, Add to Cart, Buy Now, SnackBar feedback and navigation.',
      'explanation': 'Product details are the primary business entry point for CartProvider.addProduct.',
      'hints': [
        'Use context.select to observe the current product quantity.',
        'After _addToCart succeeds, show a SnackBar with a “View” action.',
        '_buyNow adds the product first, then opens CartPage.',
      ],
    },
    'shopping-cart-part-10-product-list-entry': {
      'part': 'Part 10: Product List Entry',
      'title': 'Show the Cart Entry in Product List',
      'instruction': 'Keep product filtering, product grid and details navigation while adding the cart button to AppBar.',
      'explanation': 'Users can see cart quantity and open the cart while browsing category products.',
      'hints': [
        'Place CartIconButton in AppBar actions.',
        'Open ProductDetails when a ProductCard is tapped.',
      ],
    },
    'shopping-cart-part-11-home-entry': {
      'part': 'Part 11: Home Entry',
      'title': 'Show the Cart Button on Home',
      'instruction': 'Keep the original home structure and place CartIconButton in AppBar actions.',
      'explanation': 'The home entry lets users access the cart from the top level of the app.',
      'hints': [
        'Place CartIconButton after the account action.',
        'Open ProductList when a category is selected.',
      ],
    },
    'shopping-cart-part-12-main-navigation': {
      'part': 'Part 12: Bottom Navigation Cart Tab',
      'title': 'Add a Cart Tab to MainPage',
      'instruction': 'Use IndexedStack to preserve page state and add a cart destination to NavigationBar.',
      'explanation': 'MainPage keeps both home and cart alive as persistent top-level tabs.',
      'hints': [
        '_pages should contain both HomePage and CartPage.',
        'IndexedStack keeps the inactive page alive while switching tabs.',
      ],
    },
    'shopping-cart-part-13-provider-injection': {
      'part': 'Part 13: Global Provider Injection',
      'title': 'Inject the Cart in main.dart',
      'instruction': 'Create LocalCartService, CartRepository and CartProvider, then call loadCart during startup.',
      'explanation': 'Provider must sit above MaterialApp so product, cart and checkout pages share the same cart state.',
      'hints': [
        'Create CartRepository(service: LocalCartService()) first.',
        'Create CartProvider with ChangeNotifierProvider.',
        'Call loadCart immediately after creation.',
      ],
    },
    'shopping-cart-part-14-order-item-conversion': {
      'part': 'Part 14: Convert Cart Items to Order Items',
      'title': 'Convert CartItem to OrderItem',
      'instruction': 'Keep the original Order model and implement OrderItem.fromCartItem.',
      'explanation': 'Orders should snapshot product data instead of continuing to depend on the mutable cart.',
      'hints': [
        'Copy product ID, title, image, unit price and quantity in fromCartItem.',
        'Keep subtotal on the order item itself.',
      ],
    },
    'shopping-cart-part-15-checkout-provider': {
      'part': 'Part 15: Checkout State Integration',
      'title': 'Read and Clear the Cart During Checkout',
      'instruction': 'Implement CheckoutProvider totals, order-item conversion and post-order cart clearing.',
      'explanation': 'CheckoutProvider converts cart.items into OrderItem values and clears the cart after order creation succeeds.',
      'hints': [
        'total is cart.totalPrice plus shipping.',
        'Convert all items with OrderItem.fromCartItem.',
        'Call cart.clearCart after the order succeeds.',
        'A clear failure must not create the order twice.',
      ],
    },
    'shopping-cart-part-16-checkout-page': {
      'part': 'Part 16: Checkout UI',
      'title': 'Show Cart Products and Totals at Checkout',
      'instruction': 'Keep CheckoutPage’s product, quantity, subtotal, total and submit-order presentation.',
      'explanation': 'This is the final UI layer where cart data enters checkout.',
      'hints': [
        'Watch both CheckoutProvider and CartProvider.',
        'Iterate over cart.items in the product section.',
        'Use cart.totalPrice in the amount section.',
        'Pass CartProvider to placeOrder when submitting.',
      ],
    },
  };
}
