#include <cstdint>
#include <cstdio>
#include <cstring>
#include <thread>
#include <mutex>
#include <condition_variable>

/*
./bin/clang++ -isysroot $(xcrun --show-sdk-path) -std=c++23 unopenable_test.cpp -S -emit-llvm -o -
./bin/clang++ -isysroot $(xcrun --show-sdk-path) -std=c++23 -fpass-plugin=./lib/LowerHiddenIntrinsics.dylib unopenable_test.cpp -S -emit-llvm -o -
*/

class Foo {
public:
    int pub;
    [[campbbq::eye_unopenable]] int secret;
    int pub2;

    Foo(int p, int s, int p2) : pub(p), secret(s), pub2(p2) {}

   int get_secret() const { return secret; }
   void set_secret(int v) { secret = v; }
};

int main() {
    Foo obj(111, 42, 999);

    // ── 1. Legitimate access ──────────────────────────────────────────
    printf("=== Legitimate access (main thread) ===\n");
    printf("pub:            %d\n", obj.pub);
    printf("secret (valid): %d\n", obj.get_secret());
    printf("pub2:           %d\n", obj.pub2);

    // ── 2. Raw pointer walk through the object ────────────────────────
    // Attacker knows layout: [int pub][int secret][int pub2]
    printf("\n=== Raw memory walk (attacker) ===\n");
    int* base = reinterpret_cast<int*>(&obj);
    printf("offset 0 (pub):    %d\n", base[0]);
    printf("offset 1 (secret): %d (should be garbage)\n", base[1]);
    printf("offset 2 (pub2):   %d\n", base[2]);

    
    // ── 3. Cross-thread test ──────────────────────────────────────────
    // Thread A writes a known plaintext secret. Thread B then reads the
    // same field via the accessor. If each thread has its own key:
    //   * B's get_secret() should decrypt to garbage (wrong key)
    //   * Raw memory still holds A's ciphertext
    printf("\n=== Cross-thread access ===\n");

    constexpr int kKnownSecret = 0x12345678;

    std::mutex m;
    std::condition_variable cv;
    enum class Phase { WaitA, AWritten, BRead };
    Phase phase = Phase::WaitA;

    std::thread tA([&] {
        obj.set_secret(kKnownSecret);
        int self_read = obj.get_secret();
        int raw       = reinterpret_cast<int*>(&obj)[1];
        printf("[A] wrote %d, self get_secret()=%d (expect %d), raw=0x%08x\n",
               kKnownSecret, self_read, kKnownSecret, raw);
        {
            std::lock_guard<std::mutex> lk(m);
            phase = Phase::AWritten;
        }
        cv.notify_all();
        // Keep A alive until B has read, so the ciphertext stays put.
        std::unique_lock<std::mutex> lk(m);
        cv.wait(lk, [&] { return phase == Phase::BRead; });
    });

    std::thread tB([&] {
        std::unique_lock<std::mutex> lk(m);
        cv.wait(lk, [&] { return phase == Phase::AWritten; });
        lk.unlock();

        int cross_read = obj.get_secret();
        int raw        = reinterpret_cast<int*>(&obj)[1];
        printf("[B] get_secret()=%d (should NOT be %d if keys differ), "
               "raw=0x%08x\n",
               cross_read, kKnownSecret, raw);

        lk.lock();
        phase = Phase::BRead;
        lk.unlock();
        cv.notify_all();
    });

    tA.join();
    tB.join();

    // After both threads, the ciphertext in memory was last written by A,
    // so main thread reading via accessor — with main's own key — should
    // also produce garbage.
    printf("\n=== Main thread reading after thread A wrote ===\n");
    printf("get_secret() in main: %d (should NOT be %d)\n",
           obj.get_secret(), kKnownSecret);
    printf("raw at offset 1:       0x%08x\n",
           reinterpret_cast<int*>(&obj)[1]);
    /*
    // ── 4. memcpy — bypasses any operator overloading ─────────────────
    printf("\n=== memcpy read (attacker) ===\n");
    int stolen;
    memcpy(&stolen, reinterpret_cast<char*>(&obj) + sizeof(int), sizeof(int));
    printf("memcpy'd secret:   %d\n", stolen);    // should be garbage

    // ── 5. Pointer cast via uintptr_t arithmetic ──────────────────────
    printf("\n=== uintptr_t arithmetic (attacker) ===\n");
    uintptr_t addr = reinterpret_cast<uintptr_t>(&obj) + sizeof(int);
    int* secret_ptr = reinterpret_cast<int*>(addr);
    printf("ptr arith secret:  %d\n", *secret_ptr); // should be garbage

    // ── 6. Take address of secret legitimately ────────────────────────
    // This forces the field to be addressable — compiler must spill it.
    // The value read THROUGH your intrinsic should still be correct,
    // but raw read of that address should still be encrypted.
    printf("\n=== address-of through valid accessor ===\n");
    obj.set_secret(77);
    printf("after set to 77:   %d\n", obj.get_secret()); // should be 77
    printf("raw at same addr:  %d\n", *secret_ptr);      // should be garbage

    // ── 7. Verify surrounding fields are unaffected ───────────────────
    printf("\n=== sanity check neighbors ===\n");
    printf("pub  still:  %d\n", obj.pub);   // should be 111
    printf("pub2 still:  %d\n", obj.pub2);  // should be 999
    */

    return 0;
}
