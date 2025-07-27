-- Tạo bảng TransactionLog để lưu thông tin giao dịch
CREATE TABLE TransactionLog (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    TransactionRef NVARCHAR(50) NOT NULL,
    StudentID NVARCHAR(20) NOT NULL,
    Amount DECIMAL(18,2) NOT NULL,
    Status NVARCHAR(20) NOT NULL, -- PENDING, COMPLETED, FAILED
    InvoiceIDs NVARCHAR(MAX), -- Danh sách InvoiceID được thanh toán
    CreatedDate DATETIME NOT NULL,
    CompletedDate DATETIME NULL,
    PaymentDate DATETIME NULL
);

-- Tạo index cho TransactionRef để tìm kiếm nhanh
CREATE INDEX IX_TransactionLog_TransactionRef ON TransactionLog(TransactionRef);
CREATE INDEX IX_TransactionLog_StudentID ON TransactionLog(StudentID);

-- Stored Procedure: Lưu thông tin giao dịch
CREATE PROCEDURE SP_InsertTransactionLog
    @TransactionRef NVARCHAR(50),
    @StudentID NVARCHAR(20),
    @Amount DECIMAL(18,2),
    @Status NVARCHAR(20),
    @CreatedDate DATETIME,
    @InvoiceIDs NVARCHAR(MAX)
AS
BEGIN
    INSERT INTO TransactionLog (TransactionRef, StudentID, Amount, Status, CreatedDate, InvoiceIDs)
    VALUES (@TransactionRef, @StudentID, @Amount, @Status, @CreatedDate, @InvoiceIDs);
END;

-- Stored Procedure: Cập nhật trạng thái giao dịch
CREATE PROCEDURE SP_UpdateTransactionStatus
    @TransactionRef NVARCHAR(50),
    @Status NVARCHAR(20),
    @CompletedDate DATETIME
AS
BEGIN
    UPDATE TransactionLog 
    SET Status = @Status, CompletedDate = @CompletedDate
    WHERE TransactionRef = @TransactionRef;
END;

-- Stored Procedure: Cập nhật hóa đơn sau khi thanh toán thành công
CREATE PROCEDURE SP_UpdateInvoicesAfterPayment
    @TransactionRef NVARCHAR(50),
    @Paid BIT,
    @PaymentDate DATETIME
AS
BEGIN
    BEGIN TRANSACTION;
    
    TRY
        -- Lấy danh sách InvoiceIDs từ TransactionLog
        DECLARE @InvoiceIDs NVARCHAR(MAX);
        SELECT @InvoiceIDs = InvoiceIDs 
        FROM TransactionLog 
        WHERE TransactionRef = @TransactionRef;
        
        -- Cập nhật trạng thái các hóa đơn
        UPDATE Invoice 
        SET Paid = @Paid, 
            InvoiceDate = @PaymentDate
        WHERE InvoiceID IN (
            SELECT value 
            FROM STRING_SPLIT(@InvoiceIDs, ',')
        );
        
        -- Cập nhật trạng thái giao dịch
        UPDATE TransactionLog 
        SET Status = 'COMPLETED', 
            CompletedDate = @PaymentDate,
            PaymentDate = @PaymentDate
        WHERE TransactionRef = @TransactionRef;
        
        COMMIT TRANSACTION;
        RETURN 1; -- Success
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        RETURN 0; -- Failed
    END CATCH
END;

-- Stored Procedure: Lấy lịch sử giao dịch của sinh viên
CREATE PROCEDURE SP_GetTransactionHistory
    @StudentID NVARCHAR(20)
AS
BEGIN
    SELECT 
        t.TransactionRef,
        t.Amount,
        t.Status,
        t.CreatedDate,
        t.CompletedDate,
        t.InvoiceIDs
    FROM TransactionLog t
    WHERE t.StudentID = @StudentID
    ORDER BY t.CreatedDate DESC;
END;

-- Stored Procedure: Kiểm tra trạng thái giao dịch
CREATE PROCEDURE SP_CheckTransactionStatus
    @TransactionRef NVARCHAR(50)
AS
BEGIN
    SELECT 
        TransactionRef,
        StudentID,
        Amount,
        Status,
        CreatedDate,
        CompletedDate,
        InvoiceIDs
    FROM TransactionLog
    WHERE TransactionRef = @TransactionRef;
END;

-- Thêm cột PaymentDate vào bảng Invoice nếu chưa có
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'Invoice' AND COLUMN_NAME = 'PaymentDate')
BEGIN
    ALTER TABLE Invoice ADD PaymentDate DATETIME NULL;
END;

-- Tạo view để xem thống kê thanh toán
CREATE VIEW vw_PaymentStatistics AS
SELECT 
    t.StudentID,
    s.FullName,
    COUNT(t.TransactionRef) as TotalTransactions,
    SUM(CASE WHEN t.Status = 'COMPLETED' THEN t.Amount ELSE 0 END) as TotalPaidAmount,
    SUM(CASE WHEN t.Status = 'PENDING' THEN t.Amount ELSE 0 END) as PendingAmount,
    MAX(t.CreatedDate) as LastTransactionDate
FROM TransactionLog t
LEFT JOIN Student s ON t.StudentID = s.StudentID
GROUP BY t.StudentID, s.FullName;

-- Tạo index cho hiệu suất truy vấn
CREATE INDEX IX_Invoice_Paid ON Invoice(Paid);
CREATE INDEX IX_Invoice_StudentID ON Invoice(StudentID);
CREATE INDEX IX_TransactionLog_Status ON TransactionLog(Status);
CREATE INDEX IX_TransactionLog_CreatedDate ON TransactionLog(CreatedDate); 