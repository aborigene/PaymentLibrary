// ActionHierarchyExample.swift
// Example demonstrating automatic parent-child action relationship tracking
//
// Key Feature: When BusinessEventsClient is configured, it automatically creates a session_started 
// event whose ID becomes the parent for all first-level actions, ensuring proper session tracking.

import Foundation
import PaymentLibrary

class ActionHierarchyExample {
    
    /// Example demonstrating nested actions with automatic parent-child relationships
    /// The inner withAction calls will automatically use the outer action as their parent
    /// First-level actions will automatically have session_started as their parent
    func demonstrateActionHierarchy() async throws {
        
        // Configure BusinessEventsClient (this creates session_started event automatically)
        let endpoint = URL(string: "https://example.live.dynatrace.com/api/v2/bizevents/ingest")!
        BusinessEventsClient.shared.configure(
            endpoint: endpoint,
            auth: .apiToken("dt0c01.example-token"),
            eventProvider: "Custom Payment App"
        )
        
        print("📱 Session started - all first-level actions will have session_started as parent\n")
        
        // This first-level action will automatically have session_started as its parent
        try await BusinessEventsClient.shared.withAction(
            name: "payment_processing",
            attributes: ["amount": AnyEncodable(100.0)]
        ) {
            print("🔹 Starting payment processing (parent: session_started)")
        try await BusinessEventsClient.shared.withAction(
            name: "payment_processing",
            attributes: ["amount": AnyEncodable(100.0)]
        ) {
            print("🔹 Starting payment processing")
            
            // This will automatically have payment_processing as its parent
            try await BusinessEventsClient.shared.withAction(
                name: "validate_payment_data",
                attributes: ["card_type": AnyEncodable("visa")]
            ) {
                print("  🔸 Validating payment data")
                await simulateWork(duration: 0.5)
                
                // This will automatically have validate_payment_data as its parent
                try await BusinessEventsClient.shared.withAction(
                    name: "check_card_format",
                    attributes: ["format": AnyEncodable("16-digit")]
                ) {
                    print("    🔸 Checking card format")
                    await simulateWork(duration: 0.3)
                }
                
                // This is a sibling to check_card_format, both have validate_payment_data as parent
                try await BusinessEventsClient.shared.withAction(
                    name: "verify_expiry_date",
                    attributes: ["expiry": AnyEncodable("12/26")]
                ) {
                    print("    🔸 Verifying expiry date")
                    await simulateWork(duration: 0.2)
                }
            }
            
            // This will automatically have payment_processing as its parent (sibling to validate_payment_data)  
            try await BusinessEventsClient.shared.withAction(
                name: "process_transaction",
                attributes: ["gateway": AnyEncodable("stripe")]
            ) {
                print("  🔸 Processing transaction")
                await simulateWork(duration: 1.0)
                
                // This will automatically have process_transaction as its parent
                try await BusinessEventsClient.shared.withAction(
                    name: "send_to_gateway",
                    attributes: ["endpoint": AnyEncodable("api.stripe.com")]
                ) {
                    print("    🔸 Sending to payment gateway")
                    await simulateWork(duration: 0.8)
                }
                
                // Another child of process_transaction
                try await BusinessEventsClient.shared.withAction(
                    name: "update_payment_status",
                    attributes: ["status": AnyEncodable("completed")]
                ) {
                    print("    🔸 Updating payment status")
                    await simulateWork(duration: 0.3)
                }
            }
            
            print("🔹 Payment processing completed")
        }
    }
    
    /// Example showing how you can still explicitly set parent relationships if needed
    func demonstrateExplicitParentRelationship() async throws {
        var customParentActionId: UUID?
        
        // Create a custom parent action
        try await BusinessEventsClient.shared.withAction(
            name: "custom_parent_action",
            attributes: ["type": AnyEncodable("custom")]
        ) {
            customParentActionId = BusinessEventsClient.shared.currentActionId
            print("🔹 Custom parent action started")
            await simulateWork(duration: 0.2)
        }
        
        // Later, use the saved parent ID explicitly
        try await BusinessEventsClient.shared.withAction(
            name: "child_with_explicit_parent",
            attributes: ["explicit": AnyEncodable(true)],
            parentActionId: customParentActionId  // Explicit parent override
        ) {
            print("🔸 Child action with explicit parent relationship")
            await simulateWork(duration: 0.3)
        }
    }
    
    /// Example demonstrating session-based parent relationships
    /// All first-level actions automatically inherit session_started as parent
    func demonstrateSessionBasedParenting() async throws {
        print("🔹 Demonstrating session-based parenting")
        
        // Multiple independent first-level actions - all will have session_started as parent
        try await BusinessEventsClient.shared.withAction(
            name: "user_login",
            attributes: ["method": AnyEncodable("biometric")]
        ) {
            print("  🔸 User login (parent: session_started)")
            await simulateWork(duration: 0.3)
        }
        
        try await BusinessEventsClient.shared.withAction(
            name: "load_dashboard", 
            attributes: ["widgets": AnyEncodable(5)]
        ) {
            print("  🔸 Load dashboard (parent: session_started)")
            await simulateWork(duration: 0.4)
        }
        
        try await BusinessEventsClient.shared.withAction(
            name: "check_notifications",
            attributes: ["count": AnyEncodable(3)]
        ) {
            print("  🔸 Check notifications (parent: session_started)")
            await simulateWork(duration: 0.2)
        }
        
        print("🔹 All first-level actions automatically linked to session_started")
    }
    
    /// Example showing mixed automatic and explicit parent relationships
    func demonstrateMixedParentRelationships() async throws {
        
        try await BusinessEventsClient.shared.withAction(
            name: "mixed_example_root",
            attributes: ["example": AnyEncodable("mixed")]
        ) {
            print("🔹 Mixed example root")
            
            // This will automatically use mixed_example_root as parent
            try await BusinessEventsClient.shared.withAction(
                name: "automatic_child",
                attributes: ["type": AnyEncodable("automatic")]
            ) {
                print("  🔸 Automatic child (parent set automatically)")
                await simulateWork(duration: 0.3)
            }
            
            // This explicitly sets no parent (orphaned action)
            try await BusinessEventsClient.shared.withAction(
                name: "orphaned_child",
                attributes: ["type": AnyEncodable("orphaned")],
                parentActionId: nil  // Explicitly no parent
            ) {
                print("  🔸 Orphaned child (no parent)")
                await simulateWork(duration: 0.3)
            }
            
            print("🔹 Mixed example completed")
        }
    }
    
    private func simulateWork(duration: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}

// MARK: - Usage Examples

extension ActionHierarchyExample {
    
    /// Run all examples
    func runAllExamples() async {
        print("\n=== PaymentLibrary Action Hierarchy Examples ===\n")
        
        do {
            print("📋 Example 1: Automatic Action Hierarchy")
            print("────────────────────────────────────────")
            try await demonstrateActionHierarchy()
            
            print("\n📋 Example 2: Session-Based Parent Relationships")
            print("─────────────────────────────────────────────────")
            try await demonstrateSessionBasedParenting()
            
            print("\n📋 Example 3: Explicit Parent Relationships")
            print("─────────────────────────────────────────────")
            try await demonstrateExplicitParentRelationship()
            
            print("\n📋 Example 4: Mixed Parent Relationships")
            print("──────────────────────────────────────────")
            try await demonstrateMixedParentRelationships()
            
        } catch {
            print("❌ Error running examples: \(error)")
        }
        
        print("\n=== Examples Completed ===\n")
    }
}

/*
 Action Hierarchy Structure Created:

 payment_processing (root)
 ├── validate_payment_data
 │   ├── check_card_format
 │   └── verify_expiry_date
 └── process_transaction
     ├── send_to_gateway
     └── update_payment_status

 Key Features Demonstrated:
 
 1. **Automatic Parent Detection**: 
    - When withAction is called inside another withAction block, 
      the inner action automatically gets the outer action as its parent
    
 2. **Proper Context Management**: 
    - Each action sets itself as the current action during execution
    - Context is properly restored when the action completes
    
 3. **Error Handling**: 
    - Parent context is restored even if an action fails
    - Uses defer to ensure cleanup happens
    
 4. **Override Capability**: 
    - You can still explicitly set parentActionId if needed
    - Setting parentActionId to nil creates an orphaned action
    
 5. **Trace Correlation**: 
    - Parent-child relationships maintain proper trace correlation
    - All related actions share the same traceId
    - Parent span relationships are preserved

 Benefits:
 - Cleaner code: No need to manually track and pass parent IDs
 - Automatic correlation: Actions are automatically correlated in Dynatrace
 - Flexible: Can override automatic behavior when needed
 - Error-safe: Context is always properly restored
*/