use std::str::FromStr;

use nostr_sdk::prelude::*;


pub fn hello_world(pub_key:String, message:String, sig:String) -> anyhow::Result<String> {
  // let my_keys: Keys = Keys::generate();
  // // let event_id = EventId::from_bech32("note1z3lwphdc7gdf6n0y4vaaa0x7ck778kg638lk0nqv2yd343qda78sf69t6r")?;
  // let public_key = XOnlyPublicKey::from_str(&pub_key)?;

  // event.into()
  // let mut event: Event = EventBuilder::new_text_note(event_id, public_key, "🧡").to_event(&my_keys)?;

  // let my_keys2: Keys = Keys::generate();
  // let event_id2 = EventId::from_bech32("note1z3lwphdc7gdf6n0y4vaaa0x7ck778kg638lk0nqv2yd343qda78sf69t6r")?;
  // let public_key2 = XOnlyPublicKey::from_bech32("npub14rnkcwkw0q5lnmjye7ffxvy7yxscyjl3u4mrr5qxsks76zctmz3qvuftjz")?;
  // let event2: Event = EventBuilder::new_reaction(event_id2, public_key2, "🧡").to_event(&my_keys2)?;
  // Event::verify_signature(&self)

  //event.sig = event2.sig;
  // event.verify();
  Ok(String::from("a"))
}
