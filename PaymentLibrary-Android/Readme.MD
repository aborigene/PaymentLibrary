### What this is

This is a sample library to be imported into an Android application. 
This sample library will enable the Android application
to use payment functions exposed by the library.

This is specifically to simulate a library being instrumented and providing telemetry data to Dynatrace
independently of whatever agent the main applications is using.

### How to use this library

#### Build

For some reason Android Studio may not expose the necessary commands, but they can still be executed from the terminal, follow the steps below:

1. From the root folder of this repo run the following command:
   2. `./gradlew :PaymentLibrary:assembleRelease`
3. This will generate the `*.aar` for the library
4. Copy the library to your application project folder structure:
   5. `cp ..../<PaymentLibraryRootFolder>/PaymentLibrary/build/outputs/aar/PaymentLibrary-release.aar ..../MainApplicationProjectRootFolder/app/libs`
   6. Adjust the directory names accordingly
7. On your main project add this to the build.gradle.kts dependency block:
   8. `implementation(files("libs/paymentlibrary-release.aar"))`
   9. This will make your library available and then it can be used on the code.

#### How to use the library on your code

Add the entries below to the file where you want to use the library:

```
import com.dynatracese.paymentlibrary.CancellationCallback
import com.dynatracese.paymentlibrary.PaymentCallback
import com.dynatracese.paymentlibrary.PaymentClient
```

And where you need to handle payment, you will create a paymentClient instance:

```
val paymentClient = PaymentClient("TEST_ONLY", this)
```

If you use the "TEST_ONLY" keyword no call will be made to a backend, this is the standard right now as the backend for this library has not been built yet,
in the future the endpoint for the API should be used and a request to backend should be made to actually make a payment.

To actually receive a payment the block below servers as an example:

```
paymentClient.receivePayment(
                        amount = amount,
                        creditCardNumber = creditCard, // Exemplo de dados
                        vendorName = "Loja de Exemplo",
                        vendorId = "vendor_02",
                        callback = object : PaymentCallback {
                            override fun onPaymentSuccess(transactionId: String) {
                                // O pagamento foi bem-sucedido.
                                // Aqui você pode atualizar o saldo, mostrar uma mensagem de sucesso
                                // ou navegar de volta para a tela inicial.
                                //Toast.makeText(this@PaymentActivity, "Pagamento realizado! ID: $transactionId", Toast.LENGTH_LONG).show()
                            }

                            override fun onPaymentFailure(error: String) {
                                // Ocorreu um erro no pagamento.
                                // Exiba uma mensagem de erro para o usuário.
                                //Toast.makeText(this@PaymentActivity, "Falha no pagamento: $error", Toast.LENGTH_LONG).show()
                            }
                        }
                    )
```
