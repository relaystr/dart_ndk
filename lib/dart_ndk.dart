library dart_ndk;

/**
 * presentation layer
 * 
 */

export 'presentation_layer/api.dart';
export 'presentation_layer/ndk_config.dart';
export 'presentation_layer/ndk_request.dart';

// todo refine api and export

/**
 * common entities
 * 
 * to access all entities use 
 * import 'package:dart_ndk/entities.dart' as ndk_entities;
 * 
 */
export 'domain_layer/entities/nip_01_event.dart';
export 'domain_layer/entities/filter.dart';
export 'domain_layer/entities/nip_51_list.dart';
export 'domain_layer/entities/contact_list.dart';

/**
 *  export classes that need to be injected
 * 
 */

/// signers / verifiers
export 'domain_layer/repositories/event_verifier.dart';
export 'domain_layer/repositories/event_signer.dart';
export 'data_layer/repositories/verifiers/acinq_event_verifier.dart';
export 'data_layer/repositories/verifiers/bip340_event_verifier.dart';
export 'data_layer/repositories/signers/amber_event_signer.dart';
export 'data_layer/repositories/signers/bip340_event_signer.dart';

/// cache
export 'domain_layer/repositories/cache_manager.dart';
export 'data_layer/repositories/cache_manager/mem_cache_manager.dart';
export 'data_layer/repositories/cache_manager/db_cache_manager.dart';

/**
 * common usecases
 * 
 */

export "domain_layer/usecases/relay_manager.dart";
export "domain_layer/usecases/jit_engine.dart";
