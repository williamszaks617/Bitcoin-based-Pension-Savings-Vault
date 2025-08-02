# Bitcoin-based Pension Savings Vault

A secure pension savings system on Stacks that lets you save in both BTC and STX until retirement.

## 🌟 Features

- 💰 Save in BTC and STX
- 🔒 Locked until age 65
- 🚫 25% penalty on early withdrawals
- 📊 Real-time balance checking
- ⚡ Secure and transparent

## 🛠 Usage

### Initialize Your Vault
```clarity
(initialize-vault birth-year)
```

### Deposit Funds
```clarity
(deposit-btc amount)
(deposit-stx amount)
```

### Enable Withdrawals
```clarity
(enable-withdrawals)
```

### Withdraw Funds
```clarity
(withdraw-btc amount)
```

### Check Balance
```clarity
(get-balance user-principal)
```

## 📋 Requirements

- Minimum deposit: 1,000,000 sats/microSTX
- Maximum deposit: 100,000,000,000 sats/microSTX
- Must be born after 1940
- Retirement age: 65 years

## 🚀 Getting Started

1. Deploy contract
2. Initialize vault with birth year
3. Start depositing BTC or STX
4. Monitor your balance
5. Withdraw at retirement age
```

