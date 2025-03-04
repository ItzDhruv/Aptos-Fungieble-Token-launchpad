module launchpad_addr::tokenadd_test {
    use aptos_framework::coin;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;
    use launchpad_addr::tokenadd;
    use std::option::Option;
    use std::signer;
    use std::vector;

    #[test]
    fun test_create_fa() {
        let admin = signer::specify_address(@0x1); // Simulating admin
        tokenadd::create_fa(
            &admin,
            option::some(1_000_000), // max_supply
            b"TestToken",
            b"TTK",
            8,
            b"https://example.com/icon.png",
            b"https://example.com",
            option::some(1), // mint_fee_per_smallest_unit_of_fa
            option::some(100), // pre_mint_amount
            option::some(500) // mint_limit_per_addr
        );
    }

    #[test]
    fun test_buy_token() {
        let user = signer::specify_address(@0x2);
        let fa_obj = Object<Metadata>::specify_address(@0xFA); // Fake object address for testing
        
        tokenadd::buy_token(&user, fa_obj, 100);
    }

    #[test]
    fun test_sell_token() {
        let user = signer::specify_address(@0x2);
        let fa_obj = Object<Metadata>::specify_address(@0xFA);
        
        tokenadd::sell_token(&user, fa_obj, 10);
    }
}
