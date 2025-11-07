//
//  Secrets.kt
//  PaymentLibrary
//
//  Created by Simoes, Igor on 09/10/25.
//  Converted to Kotlin.
//

// Assumed package name, please update if incorrect
package com.dynatracese.paymentlibrary

object Secrets {

    private val obfuscatedLogToken: ByteArray = byteArrayOf(
        83, 67, 7, 84, 7, 6, 25, 112, 101, 113, 98, 1, 126, 103, 109, 4, 98, 98, 103, 0, 101, 109,
        4, 126, 109, 117, 102, 125, 123, 121, 125, 25, 101, 99, 99, 102, 116, 102, 113, 109, 110,
        123, 112, 99, 4, 124, 99, 116, 116, 109, 112, 4, 123, 96, 127, 122, 96, 97, 98, 97, 103,
        113, 114, 97, 100, 123, 120, 123, 117, 2, 118, 124, 118, 103, 110, 124, 1, 124, 101, 98,
        125, 97, 5, 118, 96, 5, 121, 110, 127, 112, 124, 5, 112, 110, 97, 100
    )
    private const val logSecretKey: Byte = 55

    private val obfuscatedBizToken: ByteArray = byteArrayOf(
        99, 115, 55, 100, 55, 54, 41, 52, 85, 48, 72, 79, 49, 78, 76, 85, 95, 68, 95, 83, 72, 79,
        82, 66, 76, 77, 93, 84, 52, 70, 80, 41, 85, 80, 84, 79, 77, 69, 82, 73, 65, 78, 68, 87,
        66, 84, 80, 78, 75, 66, 50, 78, 52, 53, 73, 51, 85, 51, 53, 86, 52, 73, 77, 66, 74, 94,
        67, 78, 82, 93, 66, 64, 84, 72, 64, 83, 95, 94, 70, 69, 87, 51, 49, 69, 65, 78, 84, 52,
        73, 83, 75, 87, 51, 74, 81, 83
    )
    private const val bizSecretKey: Byte = 7

    // ----------------------------------------------------

    /**
     * Deobfuscates and returns the token at runtime.
     */
    val dynatraceLogIngestToken: String
        get() = deobfuscate(obfuscatedLogToken, logSecretKey)

    val dynatraceBusinessEventIngestToken: String
        get() = deobfuscate(obfuscatedBizToken, bizSecretKey)

    const val dynatraceTenant: String = "https://bwm98081.live.dynatrace.com"

    /**
     * The function that reverses the XOR operation.
     */
    private fun deobfuscate(bytes: ByteArray, key: Byte): String {
        // --- START OF FIX ---
        // Perform the bitwise operation on Ints, as 'xor' is reliably
        // resolved for Ints. Then cast the result back to a Byte.
        val deobfuscatedBytes = bytes.map {
            (it.toInt() xor key.toInt()).toByte()
        }.toByteArray()
        // --- END OF FIX ---

        return try {
            // Convert the byte array to a UTF-8 string
            String(deobfuscatedBytes, Charsets.UTF_8)
        } catch (e: Exception) {
            "" // Match Swift's "?? """ behavior on failure
        }
    }
}