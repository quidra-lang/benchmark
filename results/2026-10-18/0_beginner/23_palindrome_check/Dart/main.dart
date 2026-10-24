void main() {
    for (final phrase in ['Never odd or even', 'Race a car', 'Was it a car or a cat I saw?', 'Hello, World!',
        'Step on no pets.', 'No lemon, no melon']) {
        final clean = phrase.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
        final palindrome = clean == clean.split('').reversed.join();
        print('$phrase -> ${palindrome?'yes':'no'}');
    }
}
