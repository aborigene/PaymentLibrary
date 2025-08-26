# Keep all public classes and their public members.
# This ensures that external applications can call your library's public API.
-keep public class com.dynatracese.paymentlibrary.** {
    public *;
}

# Keep all public interfaces in a specific package and its sub-packages.
-keep public interface com.dynatracese.paymentlibrary.** {
    public *;
}
