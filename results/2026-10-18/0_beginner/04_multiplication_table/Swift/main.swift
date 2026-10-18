for i in 1...9 {
    var row = ""
    for j in 1...9 {
        let product = String(i * j)
        row += String(repeating: " ", count: 3 - product.count) + product
    }
    print(row)
}
