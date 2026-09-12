Column(
  mainAxisAlignment: MainAxisAlignment.center,
  crossAxisAlignment: CrossAxisAlignment.center,
  children: [
    Text(
      'Flutter 开发课程',
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
      ),
    ),
    SizedBox(height: 12),
    Text(
      'RM 99',
      style: TextStyle(
        fontSize: 20,
        color: Colors.blue,
      ),
    ),
    SizedBox(height: 20),
    ElevatedButton(
      onPressed: null,
      child: Text('立即购买'),
    ),
  ],
)