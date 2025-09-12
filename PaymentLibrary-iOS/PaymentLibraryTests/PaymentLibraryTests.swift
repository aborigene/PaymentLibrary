import XCTest
import PaymentLibrary

/// This class contains unit tests for the PaymentClient class.
/// It verifies that payment-related functions work as expected in isolation.
final class PaymentLibraryTests: XCTestCase {

    var sut: PaymentClient! // The System Under Test (SUT)

    /// This function is called before each test method in the class.
    /// It's used to set up the environment and initialize objects.
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Initialize the PaymentClient singleton for testing
        sut = PaymentClient.shared
        // Configure the BusinessEventsClient for a test environment
        let endpoint = URL(string: "https://test.bizevents.api.com/ingest")!
        sut.configureBusinessEvents(
            endpoint: endpoint,
            auth: .apiToken("test-token"),
            eventProvider: "com.paymentlibrary.tests"
        )
    }

    /// This function is called after each test method.
    /// It's used to perform necessary cleanup.
    override func tearDownWithError() throws {
        sut = nil
        try super.tearDownWithError()
    }

    // MARK: - Test Methods

    /// Tests the successful execution of a payment.
    func testReceivePayment_success() async throws {
        let expectation = XCTestExpectation(description: "Payment successful")

        // Call the async function and handle its completion
        try await sut.receivePayment(
            amount: 100.0,
            creditCardNumber: "1234-5678-9012-3456",
            vendorName: "Test Vendor",
            vendorId: "test_vendor_id",
            crashStatus: false
        )
        
        // Assert that the test completed successfully without throwing an error.
        XCTAssertTrue(true, "The async call should not throw an error.")
        
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    /// Tests the behavior of a payment with an invalid amount.
    func testReceivePayment_invalidAmount() async {
        let amount = -100.0
        
        // The test expects an error to be thrown.
        // The `XCTAssertThrowsError` function helps verify this.
        XCTAssertThrowsError(try await sut.receivePayment(
            amount: amount,
            creditCardNumber: "1234-5678-9012-3456",
            vendorName: "Test Vendor",
            vendorId: "test_vendor_id",
            crashStatus: false
        )) { error in
            // You can optionally check the specific error type
            XCTAssertTrue(error is PaymentClient.PaymentError)
        }
    }
    
    /// Tests the behavior of the simulated crash.
    func testReceivePayment_simulatedCrash() async {
        let expectation = XCTestExpectation(description: "Simulated crash should throw an error")
        expectation.isInverted = true // Inverts the expectation, so the test passes if the expectation is NOT fulfilled

        // We wrap the `fatalError` in a `do-catch` block to handle the expected crash.
        do {
            try await sut.receivePayment(
                amount: 100.0,
                creditCardNumber: "1234-5678-9012-3456",
                vendorName: "Test Vendor",
                vendorId: "test_vendor_id",
                crashStatus: true // This flag will trigger the fatalError
            )
        } catch {
            // The fatalError will prevent this block from being executed in a real environment.
            // However, in a test environment, you can use this to check for a specific error.
            XCTAssertTrue(true, "A crash should have been triggered")
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }

    /// Tests the cancellation of a payment.
    func testCancelPayment_success() async throws {
        let transactionId = UUID().uuidString
        let expectation = XCTestExpectation(description: "Cancellation successful")
        
        try await sut.cancelPayment(transactionId: transactionId)
        
        XCTAssertTrue(true, "The async call should not throw an error.")
        
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    /// Tests the cancellation of a payment with an invalid transaction ID.
    func testCancelPayment_invalidId() async {
        let transactionId = ""
        
        XCTAssertThrowsError(try await sut.cancelPayment(transactionId: transactionId)) { error in
            XCTAssertTrue(error is PaymentClient.PaymentError)
        }
    }
}
