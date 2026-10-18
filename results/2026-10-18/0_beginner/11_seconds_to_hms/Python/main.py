for total in [0, 59, 3725, 45296, 86400, 312047]:
    hours, remaining = divmod(total, 3600)
    minutes, seconds = divmod(remaining, 60)
    print(f"{total} seconds = {hours:02d}:{minutes:02d}:{seconds:02d}")
