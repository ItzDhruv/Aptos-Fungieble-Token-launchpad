module launchpad_addr::tokenadd{

    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::coin;
    use aptos_std::table::{Self, Table};
    
    use aptos_framework::aptos_account;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, Metadata};
    use aptos_framework::object::{Self, Object, ObjectCore};
    use aptos_framework::primary_fungible_store;


     const EONLY_ADMIN_CAN_UPDATE_CREATOR: u64 = 1;
    /// Only admin can set pending admin
    const EONLY_ADMIN_CAN_SET_PENDING_ADMIN: u64 = 2;
    /// Sender is not pending admin
    const ENOT_PENDING_ADMIN: u64 = 3;
    /// Only admin can update mint fee collector
    const EONLY_ADMIN_CAN_UPDATE_MINT_FEE_COLLECTOR: u64 = 4;
    /// No mint limit
    const ENO_MINT_LIMIT: u64 = 5;
    /// Mint limit reached
    const EMINT_LIMIT_REACHED: u64 = 6;

    /// Default to mint 0 amount to creator when creating FA
    const DEFAULT_PRE_MINT_AMOUNT: u64 = 0;
    /// Default mint fee per smallest unit of FA denominated in oapt (smallest unit of APT, i.e. 1e-8 APT)
    const DEFAULT_mint_fee_per_smallest_unit_of_fa: u64 = 0;

    #[event]
    struct CreateFAEvent has store, drop {
        creator_addr: address,
        fa_owner_obj: Object<FAOwnerObjConfig>,
        fa_obj: Object<Metadata>,
        max_supply: Option<u128>,
        name: String,
        symbol: String,
        decimals: u8,
        icon_uri: String,
        project_uri: String,
        mint_fee_per_smallest_unit_of_fa: u64,
        pre_mint_amount: u64,
        mint_limit_per_addr: Option<u64>,
    }

    #[event]
    struct MintFAEvent has store, drop {
        fa_obj: Object<Metadata>,
        amount: u64,
        recipient_addr: address,
        total_mint_fee: u64,
    }

    struct Treasury has key {
    balance: u64, // Stores total APT balance collected from buys
}


    /// Unique per FA
    /// We need this object to own the FA object instead of contract directly owns the FA object
    /// This helps us avoid address collision when we create multiple FAs with same name
    struct FAOwnerObjConfig has key {
        // Only thing it stores is the link to FA object
        fa_obj: Object<Metadata>
    }

    /// Unique per FA
    struct FAController has key {
        mint_ref: fungible_asset::MintRef,
        burn_ref: fungible_asset::BurnRef,
        transfer_ref: fungible_asset::TransferRef,
    }

    /// Unique per FA
    struct MintLimit has store {
        limit: u64,
        mint_tracker: Table<address, u64>,
    }

    /// Unique per FA
    struct FAConfig has key {
        // Mint fee per FA denominated in oapt (smallest unit of APT, i.e. 1e-8 APT)
        mint_fee_per_smallest_unit_of_fa: u64,
        mint_limit: Option<MintLimit>,
        fa_owner_obj: Object<FAOwnerObjConfig>,
    }

    /// Global per contract
    struct Registry has key {
        fa_objects: vector<Object<Metadata>>,
    }

    /// Global per contract
    struct Config has key {
        // admin can set pending admin, accept admin, update mint fee collector
        admin_addr: address,
        pending_admin_addr: Option<address>,
        mint_fee_collector_addr: address,
    }

   fun init_module(sender: &signer) {
    move_to(sender, Registry {
        fa_objects: vector::empty()
    });
    move_to(sender, Config {
        admin_addr: signer::address_of(sender),
        pending_admin_addr: option::none(),
        mint_fee_collector_addr: signer::address_of(sender),
    });
    move_to(sender, Treasury { balance: 0 }); // Initialize Treasury
}


     public entry fun set_pending_admin(sender: &signer, new_admin: address) acquires Config {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<Config>(@launchpad_addr);
        assert!(is_admin(config, sender_addr));
        config.pending_admin_addr = option::some(new_admin);
    }

    /// Accept admin of the contract
    public entry fun accept_admin(sender: &signer) acquires Config {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<Config>(@launchpad_addr);
        assert!(config.pending_admin_addr == option::some(sender_addr), ENOT_PENDING_ADMIN);
        config.admin_addr = sender_addr;
        config.pending_admin_addr = option::none();
    }

    public entry fun create_fa(
    sender: &signer,
    max_supply: Option<u128>,
    name: String,
    symbol: String,
    decimals: u8,
    icon_uri: String,
    project_uri: String,
    mint_fee_per_smallest_unit_of_fa: Option<u64>,
    pre_mint_amount: Option<u64>,
    mint_limit_per_addr: Option<u64>
) acquires Registry, FAController   {

        let sender_addr = signer::address_of(sender);

        let fa_owner_obj_constructor_ref = &object::create_object(@launchpad_addr);
        let fa_owner_obj_signer = &object::generate_signer(fa_owner_obj_constructor_ref);

        let fa_obj_constructor_ref = &object::create_named_object(
            fa_owner_obj_signer,
            *string::bytes(&name),
        );
        let fa_obj_signer = &object::generate_signer(fa_obj_constructor_ref);

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            fa_obj_constructor_ref,
            max_supply,
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri
        );
        let fa_obj = object::object_from_constructor_ref(fa_obj_constructor_ref);
        move_to(fa_owner_obj_signer, FAOwnerObjConfig {
            fa_obj,
        });
        let fa_owner_obj = object::object_from_constructor_ref(fa_owner_obj_constructor_ref);
        let mint_ref = fungible_asset::generate_mint_ref(fa_obj_constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(fa_obj_constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(fa_obj_constructor_ref);
        move_to(fa_obj_signer, FAController {
            mint_ref,
            burn_ref,
            transfer_ref,
        });
        move_to(fa_obj_signer, FAConfig {
            mint_fee_per_smallest_unit_of_fa: *option::borrow_with_default(&mint_fee_per_smallest_unit_of_fa, &DEFAULT_mint_fee_per_smallest_unit_of_fa),
            mint_limit: if (option::is_some(&mint_limit_per_addr)) {
                option::some(MintLimit {
                    limit: *option::borrow(&mint_limit_per_addr),
                    mint_tracker: table::new()
                })
            } else {
                option::none()
            },
            fa_owner_obj,
        });

        let registry = borrow_global_mut<Registry>(@launchpad_addr);
        vector::push_back(&mut registry.fa_objects, fa_obj);

        event::emit(CreateFAEvent {
            creator_addr: sender_addr,
            fa_owner_obj,
            fa_obj,
            max_supply,
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri,
            mint_fee_per_smallest_unit_of_fa: *option::borrow_with_default(&mint_fee_per_smallest_unit_of_fa, &DEFAULT_mint_fee_per_smallest_unit_of_fa),
            pre_mint_amount: *option::borrow_with_default(&pre_mint_amount, &DEFAULT_PRE_MINT_AMOUNT),
            mint_limit_per_addr,
        });

        if (*option::borrow_with_default(&pre_mint_amount, &DEFAULT_PRE_MINT_AMOUNT) > 0) {
            let amount = *option::borrow(&pre_mint_amount);
            mint_fa_internal(sender, fa_obj, amount, 0);
        }
         


    }

    fun mint_fa_internal(
        sender: &signer,
        fa_obj: Object<Metadata>,
        amount: u64,
        total_mint_fee: u64,
    ) acquires FAController {
        let sender_addr = signer::address_of(sender);
        let fa_obj_addr = object::object_address(&fa_obj);

        let fa_controller = borrow_global<FAController>(fa_obj_addr);
        primary_fungible_store::mint(&fa_controller.mint_ref, sender_addr, amount);

        event::emit(MintFAEvent {
            fa_obj,
            amount,
            recipient_addr: sender_addr,
            total_mint_fee,
        });
    }

    fun is_admin(config: &Config, sender: address): bool {
        if (sender == config.admin_addr) {
            true
        } else {
            if (object::is_object(@launchpad_addr)) {
                let obj = object::address_to_object<ObjectCore>(@launchpad_addr);
                object::is_owner(obj, sender)
            } else {
                false
            }
        }
    }

//    public entry fun buy_token(
//         sender: &signer,
//         fa_obj: Object<Metadata>,
//         apt_amount: u64
//     ) acquires Config, FAController, FAConfig {
//         let _sender_addr = signer::address_of(sender);
//         let fa_obj_addr = object::object_address(&fa_obj);
        
//         let fa_config = borrow_global<FAConfig>(fa_obj_addr);
//         let mint_fee_per_unit = fa_config.mint_fee_per_smallest_unit_of_fa;
        
//         assert!(mint_fee_per_unit > 0, ENO_MINT_LIMIT);
        
//         // Calculate how many tokens the user will receive
//         let token_amount = apt_amount / mint_fee_per_unit;
//         assert!(token_amount > 0, ENO_MINT_LIMIT);
        
//         // Transfer APT from user to mint fee collector
//         let config = borrow_global<Config>(@launchpad_addr);
//        coin::transfer<0x1::aptos_coin::AptosCoin>(sender, config.mint_fee_collector_addr, apt_amount);


        
//         // Mint tokens to the user
//         mint_fa_internal(sender, fa_obj, token_amount, apt_amount);
//     }


   public entry fun buy_token(
    sender: &signer,
    fa_obj: Object<Metadata>,
    apt_amount: u64
) acquires  FAController, FAConfig, Treasury {
    let sender_addr = signer::address_of(sender);
    let fa_obj_addr = object::object_address(&fa_obj);
    
    let fa_config = borrow_global<FAConfig>(fa_obj_addr);
    let mint_fee_per_unit = fa_config.mint_fee_per_smallest_unit_of_fa;
    
    assert!(mint_fee_per_unit > 0, ENO_MINT_LIMIT);
    
    let token_amount = apt_amount / mint_fee_per_unit;
    assert!(token_amount > 0, ENO_MINT_LIMIT);

    // Fix: Place this inside the function
    let treasury = borrow_global_mut<Treasury>(@launchpad_addr);
    treasury.balance = treasury.balance + apt_amount;

    mint_fa_internal(sender, fa_obj, token_amount, apt_amount);
}


        // public entry fun sell_token(
        //     sender: &signer,
        //     fa_obj: Object<Metadata>,
        //     token_amount: u64
        // ) acquires Config, FAController, FAConfig {
        //     let sender_addr = signer::address_of(sender);
        //     let fa_obj_addr = object::object_address(&fa_obj);
            
        //     let fa_config = borrow_global<FAConfig>(fa_obj_addr);
        //     let mint_fee_per_unit = fa_config.mint_fee_per_smallest_unit_of_fa;
            
        //     assert!(mint_fee_per_unit > 0, ENO_MINT_LIMIT);
            
        //     // Calculate APT amount
        //     let apt_amount = token_amount * mint_fee_per_unit;
        //     assert!(apt_amount > 0, ENO_MINT_LIMIT);
            
        //     // Burn tokens from user's balance (pass `sender_addr` instead of `&signer`)
        //     let fa_controller = borrow_global<FAController>(fa_obj_addr);
        //     primary_fungible_store::burn(&fa_controller.burn_ref, sender_addr, token_amount);
            
        //     // Transfer APT to the user (pass `sender` instead of `sender_addr`)
        //     let config = borrow_global<Config>(@launchpad_addr);
        //     coin::transfer<0x1::aptos_coin::AptosCoin>(sender, config.mint_fee_collector_addr, apt_amount);
        // }


        public entry fun sell_token(
    sender: &signer,
    fa_obj: Object<Metadata>,
    token_amount: u64
) acquires  FAController, FAConfig, Treasury {
    let sender_addr = signer::address_of(sender);
    let fa_obj_addr = object::object_address(&fa_obj);
    
    let fa_config = borrow_global<FAConfig>(fa_obj_addr);
    let mint_fee_per_unit = fa_config.mint_fee_per_smallest_unit_of_fa;
    
    assert!(mint_fee_per_unit > 0, ENO_MINT_LIMIT);
    
    // **Calculate APT amount user will receive**
    let apt_amount = token_amount * mint_fee_per_unit;
    assert!(apt_amount > 0, ENO_MINT_LIMIT);
    
    // **Check if Treasury has enough APT to pay the user**
    let treasury = borrow_global_mut<Treasury>(@launchpad_addr);
    assert!(treasury.balance >= apt_amount);
    
    // **Burn tokens from user's balance**
    let fa_controller = borrow_global<FAController>(fa_obj_addr);
    primary_fungible_store::burn(&fa_controller.burn_ref, sender_addr, token_amount);
    
    // **Pay user from Treasury**
    treasury.balance = treasury.balance - apt_amount;
   coin::transfer<0x1::aptos_coin::AptosCoin>(sender, sender_addr, apt_amount);

}

public fun get_fa_objects_metadatas(
        collection_obj: Object<Metadata>
    ): (String, String, u8) {
        let name = fungible_asset::name(collection_obj);
        let symbol = fungible_asset::symbol(collection_obj);
        let decimals = fungible_asset::decimals(collection_obj);
        (symbol, name, decimals)
    }

    
}
